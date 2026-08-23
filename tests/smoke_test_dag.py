"""Fust-teszt DAG: bizonyitja, hogy a task-vegrehajtas mukodik, es hogy a
modellkonyvtarak elerhetok a task kornyezeteben (nem csak a shellben)."""

from __future__ import annotations

import pendulum
from airflow.sdk import dag, task


@dag(
    dag_id="initinfra_smoke_test",
    schedule=None,                       # 3.x: schedule, nem schedule_interval
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["initinfra"],
)
def smoke_test():
    @task
    def konyvtarak() -> dict:
        import numpy, pandas, sklearn, torch

        x = torch.randn(200, 200)
        return {
            "torch": torch.__version__,
            "cuda": torch.cuda.is_available(),
            "matmul": list((x @ x).shape),
            "pandas": pandas.__version__,
            "numpy": numpy.__version__,
            "sklearn": sklearn.__version__,
        }

    @task
    def adatbazis() -> str:
        import os
        import psycopg2

        conn = psycopg2.connect(
            host="postgres",
            dbname=os.environ["POSTGRES_APP_DB"],
            user=os.environ["POSTGRES_APP_USER"],
            password=os.environ["POSTGRES_APP_PASSWORD"],
        )
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            v = cur.fetchone()[0]
        conn.close()
        return v.split(",")[0]

    @task
    def osszegzes(libs: dict, db: str) -> None:
        print(f"KONYVTARAK: {libs}")
        print(f"ADATBAZIS:  {db}")
        assert libs["cuda"] is False, "CPU-only image-et vartunk"
        assert libs["matmul"] == [200, 200]
        print("MINDEN RENDBEN")

    osszegzes(konyvtarak(), adatbazis())


smoke_test()
