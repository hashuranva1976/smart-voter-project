FROM python:3.11-slim

# Install system dependencies needed for dlib, face_recognition, and FAISS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libopenblas-dev \
    liblapack-dev \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV CMAKE_BUILD_PARALLEL_LEVEL=1

# Pre-install dlib-bin precompiled wheel and face-recognition without compiling from source
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir dlib-bin && \
    pip install --no-cache-dir face-recognition-models Pillow Click && \
    pip install --no-cache-dir --no-deps face-recognition==1.3.0

# Copy requirements and install remaining python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY . .

# Ensure upload and known_faces folders exist
RUN mkdir -p temp_uploads known_faces

ENV PORT=10000
EXPOSE 10000

# Start with Gunicorn production WSGI server using dynamic port
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-10000} --workers 1 --threads 4 --timeout 120 app:app"]
