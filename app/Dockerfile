# Az InitInfra kozos app image-e. Ebbol fut az Airflow negy komponense,
# a Jupyter es a FastAPI vegpont is - igy egy Python kornyezet van a gepen.
FROM apache/airflow:3.3.1-python3.12

USER airflow

# 1. reteg: torch, CPU-only. Kulon retegben, mert ritkan valtozik es nagy.
# Az --index-url (nem --extra-index-url) azert kell, hogy a pip NE a PyPI
# CUDA-s buildjet huzza le: az ~2.5 GB nvidia libeket hozna magaval, amikre
# ezen a gepen sosem lesz szukseg.
RUN pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cpu \
      torch==2.9.0

# 2. reteg: minden mas. Ez valtozik gyakran, ezert van a torch utan.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
