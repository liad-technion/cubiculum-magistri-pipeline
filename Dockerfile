FROM python:3.12-slim

WORKDIR /srv

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8000

CMD ["python", "-m", "app.main"]