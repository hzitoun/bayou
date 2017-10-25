#!/bin/bash

# Copyright 2017 Rice University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

now=$(date "+%Y-%m-%d-%H-%M-%S")
echo "current time is $now"

id=$1

if [ ! -d model-$id/ ];then
	if [ ! -f model-$id.tar.gz ]; then
	    	aws s3 cp s3://vijay-bayou-data/models/model-$id.tar.gz .
    		rm -rf model-$id/
		mkdir -p model-$id/
		tar -xvzf model-$id.tar.gz -C model-$id/
		rm -rf model-$id.tar.gz
    fi
fi

output_file_name=model-$id
model_dir=model-$id
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "script, model, data directory is $SCRIPT_DIR"
export PYTHONPATH=$SCRIPT_DIR
echo "python path is $PYTHONPATH"
#splits=$2
splits=50
# sample: DATA-validation-sampled.json
# DATA=$1
ls *.json
# DATA=$3
DATA=DATA-validation-sampled.json
DATA_STEM=${DATA%.*}
echo "DATA_STEM is $DATA_STEM"
rm -f $DATA_STEM-*
python3 scripts/split.py $DATA --splits $splits
echo "finish splitting files into $splits pieces"
rm -rf splits/
mkdir -p splits/
mv $DATA_STEM-* splits/
echo "finish moving splits"
rm -rf out_asts/
mkdir -p out_asts/
counter=1
for filename in splits/*.json; do
    python3 -u bayou/test/ast_quality_perf_test_model.py $filename \
        --save $model_dir/ \
        --evidence all \
        --output_file out_asts/out_asts_$counter.json 2>&1 &
    ((counter++))
done
echo "Waiting for processes to finish..."
((counter--))
for idx in $(seq 1 $counter); do
    while [ ! -f out_asts/out_asts_$idx.json ]; do
        echo $idx
        sleep 5
    done
done
echo "done processing"
rm -f merged.json
python3 scripts/merge.py out_asts/ --output_file merged.json
echo "done merging splitted files"
echo "Computing metrics..."
log=OUT-$output_file_name-$now.txt
# default --top is 3
java -jar ast_quality_perf_test-1.0-jar-with-dependencies.jar -f merged.json --metric equality-ast --top 5 >> $log 2>&1
cat $log
 
merged_file=merged.json

if [ -f $merged_file ]; then
    aws s3 cp $merged_file s3://letao/bayou-validation-results/$model_dir/
else
    echo "merged out asts file $merged_file doesn't exist"
fi

if [ -f $log ]; then
    aws s3 cp $log s3://letao/bayou-validation-results/$model_dir/
else
    echo "result metric file $log doesn't exist"
fi

end_time=$(date "+%Y-%m-%d-%H-%M-%S")
echo "execution time ranges from $now to $end_time"
