FROM python:3.10-slim-buster
RUN mkdir "api"
RUN mkdir "data"
COPY main.py api/main.py
WORKDIR api
COPY requirements.txt ./
COPY ./data/quotes.json ./data/quotes.json
RUN pip3 install -r requirements.txt
EXPOSE 80
CMD ["python3","main.py"]