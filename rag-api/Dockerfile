FROM python:3.12-slim

WORKDIR /app

# Pass ECR repo URL at build time (set by Terraform)
ARG ECR_URL
RUN if [ -n "$ECR_URL" ]; then echo "ECR_URL=$ECR_URL"; fi

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Use the ECR URL to pull the correct image or set env var for the service
ENV VLLM_URL=http://vllm.llm:8000/v1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
