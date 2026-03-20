###############################################################################
# Stage 1: builder – compile Bazel, TensorFlow wheel, CTCWordBeamSearch wheel
###############################################################################
FROM nvcr.io/nvidia/tensorflow:25.02-tf2-py3 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /src/

COPY .tf_configure.bazelrc /tmp/.tf_configure.bazelrc

RUN apt-get update && apt-get install -y apt software-properties-common wget git python3-pip python3 python3-dev pkg-config \
  libhdf5-dev llvm-15 apt-transport-https curl gnupg \
  build-essential zip unzip openjdk-21-jdk coreutils bash locales lld && \
  apt-get dist-upgrade -y && \
  locale-gen en_US.UTF-8 && \
  wget -O llvm.sh https://apt.llvm.org/llvm.sh && \
  chmod +x llvm.sh && \
  ./llvm.sh 20 all && \
  update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100 && \
  rm llvm.sh && \
  rm -rf /var/lib/apt/lists/*

# Build Bazel 7.4.1 from source
RUN mkdir -p /src/bazel-7.4.1-dist && \
  cd /src/bazel-7.4.1-dist && \
  wget https://github.com/bazelbuild/bazel/releases/download/7.4.1/bazel-7.4.1-dist.zip && \
  unzip ./bazel-7.4.1-dist.zip && \
  EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh && \
  mv output/bazel /usr/local/bin/

# Build TensorFlow 2.20.0 wheel
RUN cd /src && \
  git clone https://github.com/tensorflow/tensorflow.git && \
  mv /tmp/.tf_configure.bazelrc /src/tensorflow/.tf_configure.bazelrc && \
  cd /src/tensorflow && \
  git checkout v2.20.0 && \
  bazel build //tensorflow/tools/pip_package:wheel --repo_env=USE_PYWRAP_RULES=1 --repo_env=WHEEL_NAME=tensorflow --config=cuda --config=cuda_wheel && \
  mkdir -p /wheels && \
  cp /src/tensorflow/bazel-bin/tensorflow/tools/pip_package/wheel_house/*.whl /wheels/ && \
  pip download --no-cache-dir -d /wheels /wheels/tensorflow-*.whl

# Build CTCWordBeamSearch wheel
RUN pip install --upgrade pip setuptools wheel pybind11 && \
  cd /src && \
  git clone https://github.com/rvankoert/CTCWordBeamSearch.git && \
  cd /src/CTCWordBeamSearch && \
  pip wheel --no-deps -w /wheels .

# Clone loghi-htr, record version, and pre-build requirement wheels.
# - Skip tensorflow (custom build above) and word-beam-search (built above)
# - Use opencv-python-headless instead of opencv-python (~50 MB savings)
# - Skip build-only helpers (setuptools, wheel, pybind11) and nvidia-cudnn
#   pip package (cuDNN is provided by libcudnn9-cuda-12 apt package)
# - Strip .git history and tests from the source copy
RUN git clone https://github.com/knaw-huc/loghi-htr.git /src/loghi-htr && \
  cd /src/loghi-htr/src && \
  git --git-dir=/src/loghi-htr/.git log --format="%H" -n 1 > /src/loghi-htr/src/version_info && \
  rm -rf /src/loghi-htr/.git && \
  cd /src/loghi-htr && \
  sed -i 's/opencv_python==/opencv-python-headless==/' requirements.txt && \
  pip install --upgrade pip setuptools wheel cython pkgconfig numpy==2.4.2 && \
  pip wheel --no-cache-dir -w /wheels \
    numpy==2.4.2 \
    editdistance==0.8.1 \
    keras==3.13.2 \
    matplotlib==3.10.3 \
    opencv-python-headless==4.11.0.86 \
    tf_keras_vis==0.8.7 \
    "elasticdeform @ git+https://github.com/gvtulder/elasticdeform" \
    blinker==1.9.0 \
    fpdf==1.7.2 \
    scikit-image==0.25.2 \
    prometheus-client==0.21.1 \
    xlsxwriter==3.2.3 \
    six \
    Pillow==12.1.1 \
    "fastapi[standard]==0.115.12" \
    uvicorn==0.34.2 \
    typing-extensions==4.15.0 \
    psutil==7.0.0 \
    scipy==1.15.3 \
    vgslify==0.14.0 \
    python-bidi && \
  pip wheel --no-cache-dir --no-build-isolation -w /wheels h5py==3.15.1

###############################################################################
# Stage 2: runtime – lean CUDA-only base, no pre-installed TF stack
###############################################################################
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
# Ensure CUDA libraries are on the linker path
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}
# Disable XLA auto-clustering JIT (requires nvptx/ptxas not in runtime image)
#ENV TF_XLA_FLAGS="--tf_xla_auto_jit=0"
#ENV XLA_FLAGS="--xla_gpu_enable_xla_runtime_executable=false"

WORKDIR /src/

# Install Python and minimal runtime OS packages.
# cuda-nvrtc is needed for TF ops that use runtime compilation even when XLA
# JIT is disabled.  libcusparse/libcublas are pulled in by the base image.
RUN apt-get update && apt-get install -y --no-install-recommends \
  python3 python3-pip \
  libsm6 libxext6 \
  cuda-nvrtc-12-8 \
  locales nano libtcmalloc-minimal4t64 && \
  locale-gen en_US.UTF-8 && \
  rm -rf /var/lib/apt/lists/*

# Copy pre-built wheels and loghi-htr source (without .git or tests) from builder
COPY --from=builder /wheels /wheels
COPY --from=builder /src/loghi-htr /src/loghi-htr
# Copy CUDA nvvm device library (libdevice.10.bc) and ptxas needed by
# TensorFlow's XLA/MLIR backend to generate GPU device code at runtime.
COPY --from=builder /usr/local/cuda/nvvm /usr/local/cuda/nvvm
COPY --from=builder /usr/local/cuda/bin/ptxas /usr/local/cuda/bin/ptxas

# Install all Python packages from pre-built wheels, allowing pip to fetch
# any missing transitive dependencies (e.g. absl-py, protobuf, grpcio, etc.
# required by TensorFlow) from PyPI.
RUN rm /wheels/wheel-* ; pip install --no-cache-dir --break-system-packages --find-links /wheels /wheels/*.whl && \
  rm -rf /wheels /root/.cache/pip /tmp/* && \
  find /usr -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null; \
  find /usr -name '*.pyc' -delete 2>/dev/null; \
  true

WORKDIR /src/loghi-htr/src
