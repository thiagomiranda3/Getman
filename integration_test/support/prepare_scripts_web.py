"""Install the real pdfx prerequisite into a temporary integration-only index.

The product index is restored by run_scripts_web.sh's EXIT trap. PDF.js assets
are downloaded before the hermetic browser session starts, never from JS.
"""
import pathlib
import sys
import urllib.request

port, directory = sys.argv[1:]
root = pathlib.Path(directory)
for name in ['pdf.min.mjs', 'pdf.worker.min.mjs']:
    urllib.request.urlretrieve(
        'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.6.82/build/' + name,
        root / name,
    )
index = pathlib.Path('web/index.html')
source = index.read_text()
bootstrap = f'''<script type="module">
import * as pdfjsLib from 'http://127.0.0.1:{port}/pdfjs/pdf.min.mjs';
globalThis.pdfjsLib = pdfjsLib;
pdfjsLib.GlobalWorkerOptions.workerSrc = 'http://127.0.0.1:{port}/pdfjs/pdf.worker.min.mjs';
const bootstrap = document.createElement('script');
bootstrap.src = 'flutter_bootstrap.js';
document.body.appendChild(bootstrap);
</script>'''
index.write_text(source.replace('<script src="flutter_bootstrap.js" async></script>', bootstrap))
