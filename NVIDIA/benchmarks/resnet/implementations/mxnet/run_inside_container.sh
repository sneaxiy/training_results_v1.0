#!/bin/bash

# Copyright (c) 2018-2021, NVIDIA CORPORATION. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euxo pipefail

# Vars without defaults
: "${DGXSYSTEM:?DGXSYSTEM not set}"
: "${DATADIR:?DATADIR not set}"

# Vars with defaults
: "${NEXP:=5}"
: "${DATESTAMP:=$(date +'%y%m%d%H%M%S%N')}"
: "${CLEAR_CACHES:=1}"
: "${LOGDIR:=$(pwd)/results}"
: "${COPY_DATASET:=}"

echo $COPY_DATASET

if [ ! -z $COPY_DATASET ]; then
    readonly copy_datadir=$COPY_DATASET
    mkdir -p "${DATADIR}"
    ${CODEDIR}/copy-data.sh "${copy_datadir}" "${DATADIR}"
    ls ${DATADIR}
fi
export DATADIR

# Other vars
readonly _seed_override=${SEED:-}
readonly _config_file="./config_${DGXSYSTEM}.sh"
readonly _logfile_base="${LOGDIR}/${DATESTAMP}"
readonly _cont_name=image_classification

# MLPerf vars
MLPERF_HOST_OS=$(
    source /etc/os-release
    source /etc/dgx-release || true
    echo "${PRETTY_NAME} / ${DGX_PRETTY_NAME:-???} ${DGX_OTA_VERSION:-${DGX_SWBUILD_VERSION:-???}}"
)
export MLPERF_HOST_OS

# Setup directories
mkdir -p "${LOGDIR}"

# Get list of envvars to pass to docker
source "./config_${DGXSYSTEM}_common.sh"
source "${_config_file}"
export SEED="${SEED:-}"

ulimit -s 67108864
ulimit -l unlimited 

# sleep 30

# Run experiments
for _experiment_index in $(seq 1 "${NEXP}"); do
    (
        echo "Beginning trial ${_experiment_index} of ${NEXP}"

        # Print system info
        python -c "
import mlperf_log_utils
from mlperf_logging.mllog import constants

mlperf_log_utils.mlperf_submission_log(constants.RESNET)"

        # Clear caches
        if [ "${CLEAR_CACHES}" -eq 1 ]; then
	    (sync && /sbin/sysctl vm.drop_caches=3) || true
            python -c "
import mlperf_log_utils
from mlperf_logging.mllog import constants

mlperf_log_utils.mx_resnet_print_event(key=constants.CACHE_CLEAR, val=True)"
        fi

        # Run experiment
        export SEED=${_seed_override:-$RANDOM}
        ./run_and_time.sh
    ) |& tee "${_logfile_base}_${_experiment_index}.log"
done
