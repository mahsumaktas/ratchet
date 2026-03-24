#!/usr/bin/env bash
# ar-probe.sh — Environment probing: auto-detect project type, tools, frameworks
# Usage: ar-probe.sh [project_root]
# Output: JSON to stdout
set -euo pipefail

ROOT="${1:-$PWD}"

AR_ROOT="$ROOT" python3 -c "
import os, json, glob

root = os.environ['AR_ROOT']
env = {
    'languages': [],
    'test_runners': [],
    'linters': [],
    'type_checkers': [],
    'formatters': [],
    'frameworks': [],
    'ci': [],
    'monorepo': False,
    'package_manager': None,
}

def exists(*paths):
    return any(os.path.exists(os.path.join(root, p)) for p in paths)

def has_ext(ext):
    for dirpath, _, filenames in os.walk(root):
        if any(skip in dirpath for skip in ['node_modules', '.git', 'vendor', 'dist', 'build', '__pycache__', '.venv', 'venv']):
            continue
        for f in filenames:
            if f.endswith(ext):
                return True
    return False

# --- Languages ---
if exists('package.json'):
    env['languages'].append('javascript')
    if exists('tsconfig.json'): env['languages'].append('typescript')
if exists('pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt'):
    env['languages'].append('python')
if exists('Cargo.toml'): env['languages'].append('rust')
if exists('go.mod'): env['languages'].append('go')
if exists('Gemfile'): env['languages'].append('ruby')
if exists('pom.xml', 'build.gradle', 'build.gradle.kts'):
    env['languages'].append('java')
if has_ext('.sh') and not env['languages']:
    env['languages'].append('shell')

# --- Test Runners ---
if exists('package.json'):
    try:
        with open(os.path.join(root, 'package.json')) as pf:
            pkg = json.load(pf)
        deps = {**pkg.get('devDependencies', {}), **pkg.get('dependencies', {})}
        scripts = pkg.get('scripts', {})
        if 'vitest' in deps: env['test_runners'].append('vitest')
        elif 'jest' in deps or '@jest/core' in deps: env['test_runners'].append('jest')
        elif 'mocha' in deps: env['test_runners'].append('mocha')
        elif 'test' in scripts: env['test_runners'].append('npm-test')
    except: pass
if exists('pytest.ini', 'conftest.py') or (exists('pyproject.toml') and 'pytest' in (open(os.path.join(root, 'pyproject.toml')).read() if exists('pyproject.toml') else '')):
    env['test_runners'].append('pytest')
if exists('Cargo.toml'): env['test_runners'].append('cargo-test')
if exists('go.mod'): env['test_runners'].append('go-test')

# --- Linters ---
if exists('.eslintrc.js', '.eslintrc.json', '.eslintrc.yml', 'eslint.config.js', 'eslint.config.mjs', 'eslint.config.ts'):
    env['linters'].append('eslint')
if exists('biome.json', 'biome.jsonc'):
    env['linters'].append('biome')
if exists('ruff.toml') or (exists('pyproject.toml') and 'ruff' in open(os.path.join(root, 'pyproject.toml')).read()):
    env['linters'].append('ruff')
if exists('Cargo.toml'): env['linters'].append('clippy')
if exists('go.mod'): env['linters'].append('go-vet')
if exists('.rubocop.yml'): env['linters'].append('rubocop')

# --- Type Checkers ---
if exists('tsconfig.json'): env['type_checkers'].append('tsc')
if exists('mypy.ini') or (exists('pyproject.toml') and 'mypy' in open(os.path.join(root, 'pyproject.toml')).read()):
    env['type_checkers'].append('mypy')
if exists('pyrightconfig.json'): env['type_checkers'].append('pyright')

# --- Formatters ---
if exists('.prettierrc', '.prettierrc.js', '.prettierrc.json', 'prettier.config.js'):
    env['formatters'].append('prettier')
if exists('Cargo.toml'): env['formatters'].append('rustfmt')
if exists('go.mod'): env['formatters'].append('gofmt')
if 'ruff' in env['linters']: env['formatters'].append('ruff-format')
elif 'python' in env['languages']:
    env['formatters'].append('black')

# --- Frameworks ---
if exists('next.config.js', 'next.config.mjs', 'next.config.ts'):
    env['frameworks'].append('nextjs')
if exists('nuxt.config.js', 'nuxt.config.ts'):
    env['frameworks'].append('nuxt')
if exists('vite.config.js', 'vite.config.ts'):
    env['frameworks'].append('vite')
if exists('angular.json'): env['frameworks'].append('angular')
if exists('svelte.config.js'): env['frameworks'].append('svelte')
if exists('manage.py') and has_ext('.py'):
    env['frameworks'].append('django')
if exists('app.py', 'wsgi.py') and 'flask' in str(open(os.path.join(root, 'requirements.txt')).read() if exists('requirements.txt') else ''):
    env['frameworks'].append('flask')
if exists('Rocket.toml'): env['frameworks'].append('rocket')

# --- CI ---
if exists('.github/workflows'): env['ci'].append('github-actions')
if exists('.gitlab-ci.yml'): env['ci'].append('gitlab-ci')
if exists('Jenkinsfile'): env['ci'].append('jenkins')
if exists('.circleci'): env['ci'].append('circleci')

# --- Monorepo ---
if exists('lerna.json', 'pnpm-workspace.yaml', 'nx.json'):
    env['monorepo'] = True
if exists('Cargo.toml'):
    try:
        content = open(os.path.join(root, 'Cargo.toml')).read()
        if '[workspace]' in content: env['monorepo'] = True
    except: pass

# --- Package Manager ---
if exists('pnpm-lock.yaml'): env['package_manager'] = 'pnpm'
elif exists('yarn.lock'): env['package_manager'] = 'yarn'
elif exists('bun.lock', 'bun.lockb'): env['package_manager'] = 'bun'
elif exists('package-lock.json'): env['package_manager'] = 'npm'
elif exists('Pipfile.lock'): env['package_manager'] = 'pipenv'
elif exists('poetry.lock'): env['package_manager'] = 'poetry'
elif exists('uv.lock'): env['package_manager'] = 'uv'

# Clean up empty lists
env = {k: v for k, v in env.items() if v}

print(json.dumps(env, indent=2))
"
