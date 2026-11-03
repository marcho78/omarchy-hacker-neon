# A bigger run with openWakeWord's recommended sizes: 20,000 samples and
# 50,000 steps. The clips already made are kept and topped up; the features are
# computed again (--overwrite) to include the new clips. The first model is
# kept as hey_trinity_v1.onnx.
set -e
cd ~/oww
. .venv/bin/activate
cp my_custom_model/hey_trinity.onnx my_custom_model/hey_trinity_v1.onnx
sed -i -e "s/^n_samples: .*/n_samples: 20000/" -e "s/^steps: .*/steps: 50000/" my_model.yaml
grep -E "^(n_samples|n_samples_val|steps):" my_model.yaml
T=openwakeword/openwakeword/train.py
echo "== STEP 1 generate clips $(date +%T)"
python $T --training_config my_model.yaml --generate_clips
echo "== STEP 2 augment clips $(date +%T)"
python $T --training_config my_model.yaml --augment_clips --overwrite
echo "== STEP 3 train model $(date +%T)"
python $T --training_config my_model.yaml --train_model
echo "== TRAINING DONE $(date +%T)"
ls -la my_custom_model
