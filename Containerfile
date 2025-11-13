FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    g++ \
    cmake \
    wget \
    perl \
    python3 \
    python3-pip \
    python3-dev \
    flex \
    bison \
    libfl-dev \
    zlib1g-dev \
    libelf-dev \
    ccache \
    autoconf \
    help2man \
    gawk \
    gperf \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    texinfo \
    libisl-dev \
    patchutils \
    && rm -rf /var/lib/apt/lists/*

ENV VERILATOR_VERSION=794247450
ENV VERILATOR_INSTALL_DIR=/usr/local

RUN set -ex && \
    git clone https://github.com/verilator/verilator.git /tmp/verilator_src && \
    cd /tmp/verilator_src && \
    echo "Checking out Verilator git hash: ${VERILATOR_VERSION}" && \
    git checkout ${VERILATOR_VERSION} && \
    git clean -fdx && \
    unset VERILATOR_ROOT && \
    autoconf && \
    ./configure --prefix=${VERILATOR_INSTALL_DIR} && \
    echo "Building Verilator..." && \
    make && \
    echo "Installing Verilator..." && \
    make install && \
    cd / && \
    rm -rf /tmp/verilator_src

RUN set -ex && \
        apt-get update && \
        apt-get install -y \
            gcc-riscv64-unknown-elf-newlib \
            binutils-riscv64-unknown-elf \
            gcc-riscv64-unknown-elf || true && \
        rm -rf /var/lib/apt/lists/*


WORKDIR /work
COPY --from=docker.io/astral/uv:latest /uv /uvx /bin/
RUN uv venv
RUN uv pip install cocotb==1.9.2

# RUN "echo 'source .venv/bin/activate' >> ~/.bashrc"

CMD ["source", ".venv/bin/activate", "/bin/bash"]
