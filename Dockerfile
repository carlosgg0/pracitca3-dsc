FROM python:3.11-slim

# Python logs are printed in docker console
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src/ src/

ENTRYPOINT ["python", "src/app.py"]
