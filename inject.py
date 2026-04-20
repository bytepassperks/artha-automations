import os

script_path = '/tmp/fs_embed.js'
html_path = 'dist/packages/web/index.html'

with open(script_path, 'r') as f:
    script = f.read().replace('\n', '')

with open(html_path, 'r') as f:
    html = f.read()

target = '<div id="root"></div>'
replacement = '<script>' + script + '</script>' + target

html = html.replace(target, replacement, 1)

with open(html_path, 'w') as f:
    f.write(html)

print('Injected fs_embed.js into index.html')
