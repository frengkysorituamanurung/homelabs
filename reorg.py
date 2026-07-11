import os
import shutil

base = '/root/server/gitops-repo'

def mv(src, dest):
    os.makedirs(os.path.dirname(os.path.join(base, dest)), exist_ok=True)
    if os.path.exists(os.path.join(base, src)):
        # using git mv if possible, but shutil is fine since we do git add . later
        shutil.move(os.path.join(base, src), os.path.join(base, dest))
        print(f"Moved {src} to {dest}")

def replace_in_file(filepath, old_str, new_str):
    full_path = os.path.join(base, filepath)
    if not os.path.exists(full_path):
        return
    with open(full_path, 'r') as f:
        content = f.read()
    content = content.replace(old_str, new_str)
    with open(full_path, 'w') as f:
        f.write(content)
    print(f"Updated {filepath}")

# 1. Move ArgoCD Application Manifests
mv('apps/cloudflare/cloudflared.yaml', 'kubernetes/applications/infrastructure/cloudflared.yaml')
for file in os.listdir(os.path.join(base, 'apps/ingress')):
    if file.endswith('.yaml'):
        mv(f'apps/ingress/{file}', f'kubernetes/applications/infrastructure/{file}')

# 2. Move Raw Manifests
mv('manifests/cloudflare', 'kubernetes/production/cloudflare')
mv('manifests/ingress', 'kubernetes/production/ingress')
mv('manifests/gitea-runner', 'kubernetes/production/gitea-runner')

# 3. Update the Paths in the ArgoCD Manifests
replace_in_file('kubernetes/applications/infrastructure/cloudflared.yaml', 'path: manifests/cloudflare', 'path: kubernetes/production/cloudflare')
replace_in_file('kubernetes/applications/infrastructure/gitea-runner.yaml', 'path: manifests/gitea-runner', 'path: kubernetes/production/gitea-runner')

for file in os.listdir(os.path.join(base, 'kubernetes/applications/infrastructure')):
    if file.endswith('ingress.yaml') or 'ingressroute' in file:
        replace_in_file(f'kubernetes/applications/infrastructure/{file}', 'path: manifests/ingress', 'path: kubernetes/production/ingress')

# 4. Clean up
shutil.rmtree(os.path.join(base, 'apps'), ignore_errors=True)
shutil.rmtree(os.path.join(base, 'manifests'), ignore_errors=True)
print("Cleanup complete!")
