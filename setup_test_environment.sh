#!/bin/bash

docker build -t rvcore-coco:latest . -f Containerfile

docker run --rm -it \
    -v "$(pwd)":/work/code \
    -v "$PREFIX":"$PREFIX" \
    --workdir /work \
    rvcore-coco:latest /bin/bash \
    -c "source .venv/bin/activate && /bin/bash"