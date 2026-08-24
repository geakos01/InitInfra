import asyncio, json, os, sys
import websockets

async def main():
    uri = "ws://api:8000/ws"
    kuldott = [
        {"tipus": "megtekintes", "session_id": "s-42", "termek": "pergeto-bot"},
        {"tipus": "megtekintes", "session_id": "s-42", "termek": "orso"},
        {"tipus": "kosarba",     "session_id": "s-42", "termek": "orso"},
        {"tipus": "megtekintes", "session_id": "s-99", "termek": "zsinor"},
        {"tipus": "vasarlas",    "session_id": "s-42", "osszeg": 18990},
    ]
    async with websockets.connect(uri) as ws:
        for u in kuldott:
            await ws.send(json.dumps(u))
            v = json.loads(await ws.recv())
            print(f"    -> {u['tipus']:12s} redisben={str(v['redisben']):5s} kiirt_sorok={v['kiirt_sorok']}")
    print(f"  {len(kuldott)} uzenet elkuldve")

asyncio.run(main())
