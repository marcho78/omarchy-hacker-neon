# Adds the user's own recordings to the training: the "Hey Trinity" clips to the
# positives and the normal talk to the negatives, each copied many times so they
# carry weight among the 20,000 synthetic clips (augmenting gives every copy
# different noise, echo and tone). Then augments and trains again. The current
# model is kept as hey_trinity_v2.onnx.
set -e
cd ~/oww
. .venv/bin/activate
M=my_custom_model/hey_trinity
cp my_custom_model/hey_trinity.onnx my_custom_model/hey_trinity_v2.onnx
for f in voice/wake/*.wav; do b=$(basename $f .wav); for c in $(seq -w 1 160); do cp $f $M/positive_train/${b}_$c.wav; done; done
for f in voice/talk/*.wav; do b=$(basename $f .wav); for c in $(seq -w 1 70); do cp $f $M/negative_train/${b}_$c.wav; done; done
echo "positive_train $(ls $M/positive_train | wc -l)  negative_train $(ls $M/negative_train | wc -l)"
T=openwakeword/openwakeword/train.py
echo "== STEP 2 augment clips $(date +%T)"
python $T --training_config my_model.yaml --augment_clips --overwrite
echo "== STEP 3 train model $(date +%T)"
python $T --training_config my_model.yaml --train_model
echo "== TRAINING DONE $(date +%T)"
ls -la my_custom_model
