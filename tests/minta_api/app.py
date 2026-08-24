"""MINTA vegpont - NEM a vegleges modellkod.

Az InitInfra nem szallitja a logger API-t: az ugyfelenkent kulonbozo, es a
/opt/app-ba kerul git pull-lal. Ez a fajl csak azt bizonyitja, hogy a stack
vezetekezese mukodik: websocket kifele, Redis es Postgres befele.

A valodi kod ugyanezt az utat jarja: bejon egy log -> eldonti a tipusat ->
opcionalisan Redisbe irja (SASRec session history) -> batch-esen Postgresbe.
"""

from __future__ import annotations

import asyncio
import json
import os
from contextlib import asynccontextmanager

import asyncpg
import redis.asyncio as aioredis
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

PG = dict(
    host=os.environ["POSTGRES_HOST"],
    port=int(os.environ["POSTGRES_PORT"]),
    database=os.environ["POSTGRES_APP_DB"],
    user=os.environ["POSTGRES_APP_USER"],
    password=os.environ["POSTGRES_APP_PASSWORD"],
)

BATCH_MERET = 5          # eles kodban nagyobb; itt hogy a teszt lassa
batch: list[tuple] = []
allapot: dict = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    allapot["pg"] = await asyncpg.create_pool(**PG, min_size=1, max_size=4)
    allapot["redis"] = aioredis.Redis(
        host=os.environ["REDIS_HOST"], port=int(os.environ["REDIS_PORT"])
    )
    async with allapot["pg"].acquire() as c:
        await c.execute(
            "CREATE TABLE IF NOT EXISTS esemenyek ("
            " id bigserial PRIMARY KEY,"
            " tipus text NOT NULL,"
            " session_id text,"
            " adat jsonb,"
            " erkezett timestamptz NOT NULL DEFAULT now())"
        )
    yield
    await urites()
    await allapot["pg"].close()
    await allapot["redis"].aclose()


app = FastAPI(lifespan=lifespan, title="InitInfra minta logger API")


async def urites() -> int:
    """A batch kiirasa Postgresbe. Eles kodban idozitve is fut."""
    if not batch:
        return 0
    sorok, n = list(batch), len(batch)
    batch.clear()
    async with allapot["pg"].acquire() as c:
        await c.executemany(
            "INSERT INTO esemenyek (tipus, session_id, adat) VALUES ($1, $2, $3)", sorok
        )
    return n


@app.get("/health")
async def health() -> dict:
    async with allapot["pg"].acquire() as c:
        pg_ok = await c.fetchval("SELECT 1") == 1
    return {
        "status": "ok",
        "postgres": pg_ok,
        "redis": await allapot["redis"].ping(),
        "varakozo_batch": len(batch),
    }


@app.get("/statisztika")
async def statisztika() -> dict:
    async with allapot["pg"].acquire() as c:
        rows = await c.fetch("SELECT tipus, count(*) AS db FROM esemenyek GROUP BY tipus")
    return {"esemenyek": {r["tipus"]: r["db"] for r in rows}}


@app.websocket("/ws")
async def ws(sock: WebSocket) -> None:
    await sock.accept()
    try:
        while True:
            uzenet = json.loads(await sock.receive_text())
            tipus = uzenet.get("tipus", "ismeretlen")
            sid = uzenet.get("session_id")

            # 1. Opcionalisan Redisbe: session history az inference-hez
            redis_ok = False
            if tipus == "megtekintes" and sid:
                await allapot["redis"].rpush(f"session:{sid}", json.dumps(uzenet))
                await allapot["redis"].expire(f"session:{sid}", 60 * 60 * 24 * 8)
                redis_ok = True

            # 2. Batch-esen Postgresbe
            batch.append((tipus, sid, json.dumps(uzenet)))
            kiirt = await urites() if len(batch) >= BATCH_MERET else 0

            await sock.send_text(
                json.dumps({"fogadva": tipus, "redisben": redis_ok, "kiirt_sorok": kiirt})
            )
    except WebSocketDisconnect:
        await urites()
