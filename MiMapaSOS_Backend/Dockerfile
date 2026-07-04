# Build stage
FROM python:3.10-slim

# Install system dependencies, including Node.js for Prisma
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    libpq-dev \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir honcho prisma

# Install Node Prisma CLI
COPY package.json ./
# COPY package-lock.json ./ (if it exists)
RUN npm install

# Copy application code
COPY . .

# Generate Prisma client
RUN DATABASE_URL="postgresql://dummy:dummy@dummy:5432/dummy" prisma generate

# Create Linux Procfile for Honcho
RUN echo "usuarios: PYTHONPATH=. python ms_usuarios/app.py\n\
alertas: PYTHONPATH=. python ms_alertas/app.py\n\
rutas: PYTHONPATH=. python ms_rutas/app.py\n\
geografia: PYTHONPATH=. python ms_geografia/app.py" > Procfile.prod

# Expose ports used by microservices
EXPOSE 5001 5002 5003 5004

# Run all microservices using honcho
CMD ["honcho", "start", "-f", "Procfile.prod"]