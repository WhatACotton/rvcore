# RVCORE

RVCORE is a lightweight repository for simulating and testing a RISC-V core.

Overview

- This repository contains RTL sources, testbenches, test programs, and utilities used to build and verify a simple RISC-V implementation.
- This module is aimed to develop the debug module of the RISC-V core. It provides a basic framework for simulating the core and running tests against it.
- Do not rely on this repository for production use. It is intended for educational and experimental purposes only.

Requirements

- docker environment

Quick setup

This script creates a Docker container with all necessary tools and dependencies installed.

```bash
# Prepare the test environment (installs or configures dependencies)
./setup_test_environment.sh
```

Running tests

- Use the scripts in the `tests/` directory. You can run in the Docker environment set up previously.

```bash
# Run all simulations
./tests/run_all_tests_simple.sh

# Run a single test
./tests/run_single_test.sh <testname>

# Compile C test programs (from `tests/c_programs`)
cd tests/c_programs && ./compile.sh <program.c>
```

Main directories

- `rtl/` — hardware descriptions (SystemVerilog)
- `core/` — core implementation sources
- `tests/` — test scripts, example programs, and test harnesses
- `tests/riscv_test_hex/` — precompiled RISC-V test programs from riscv-tests
- `common/` — utilities for running simulations and tests
- `deps/` — external dependencies and submodules
