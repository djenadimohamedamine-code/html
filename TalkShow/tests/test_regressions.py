"""Run: python -m unittest discover -s TalkShow/tests -v (no render required)."""
import ast
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
import types
import unittest
from unittest.mock import patch
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
# Pure/backend tests do not launch Chromium or require Playwright installed.
stub = types.ModuleType('playwright.sync_api')
stub.sync_playwright = None
with patch.dict(sys.modules, {'playwright': types.ModuleType('playwright'), 'playwright.sync_api': stub}):
    spec = importlib.util.spec_from_file_location('renderer', ROOT / 'render_talkshow.py')
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)


class Regressions(unittest.TestCase):
    def test_credits_agree_in_three_sources(self):
        raw = renderer.DEFAULTS['generique']['credits']
        ui = (ROOT / 'TALKSHOW.html').read_text()
        defaults = json.loads(re.search(r'credits: (\[.*?\])\.join', ui, re.S)[1])
        self.assertEqual('\n'.join(defaults), raw)
        template = (ROOT / 'template_generique.html').read_text()
        region = template.split('<!--CR:START-->')[1].split('<!--CR:END-->')[0]
        actual = re.findall(r'<div class="cr-(?:cat|name)">(.*?)</div>', region)
        self.assertEqual(actual, [line.lstrip('# ') for line in raw.splitlines() if line])
        self.assertIn('مالك مشكة', actual)
        self.assertEqual(len(renderer.parse_credits(raw)), 9)

    def test_fit_preserves_short_text_and_shrinks_long_text(self):
        for template, a, b, first, second, width in [('synthe3','nameTxt','roleTxt',78,50,1602), ('titre3','mainTxt','subTxt',68,38,1334)]:
            src = (ROOT / f'template_{template}.html').read_text()
            fit = re.search(r'    function fit\(\) \{.*?\n    \}', src, re.S)[0]
            script = '''const assert=require('node:assert/strict');
let glyphWidth=500;
const element=()=>({style:{},clientWidth:WIDTH,offsetWidth:WIDTH});
let FIRST=element(), SECOND=element();
const document={createRange:()=>({selectNodeContents(e){this.el=e},getBoundingClientRect(){return {width:glyphWidth*parseFloat(this.el.style.fontSize)/BASE}}})};
FIT
fit();assert.equal(FIRST.style.fontSize,'BASEpx');assert.equal(SECOND.style.fontSize,'ROLEpx');
glyphWidth=2000;fit();assert.ok(parseFloat(FIRST.style.fontSize)<BASE);
assert.ok(parseFloat(SECOND.style.fontSize)<parseFloat(FIRST.style.fontSize));
glyphWidth=500;fit();assert.equal(FIRST.style.fontSize,'BASEpx');
'''.replace('WIDTH',str(width)).replace('FIRST',a).replace('SECOND',b).replace('FIT',fit).replace('BASE',str(first)).replace('ROLE',str(second))
            subprocess.run(['node','-e',script],check=True)

    def test_preview_rejects_busy_and_releases_lock_on_success_and_failure(self):
        real_server = ThreadingHTTPServer
        ready = threading.Event()
        servers = []
        def create_server(address, handler):
            server = real_server(('127.0.0.1',0),handler)
            servers.append(server)
            ready.set()
            return server
        def post():
            req = Request('http://127.0.0.1:%d/preview-render' % servers[0].server_port,
                          data=b'{"tpl":"synthe3"}',method='POST')
            try:
                with urlopen(req,timeout=5) as response:
                    return response.status,json.load(response)
            except HTTPError as response:
                return response.code,json.load(response)
        with patch('http.server.ThreadingHTTPServer',create_server), patch.object(renderer,'_queue_load'):
            worker=threading.Thread(target=renderer.serve,kwargs={'open_browser':False},daemon=True)
            worker.start()
            self.assertTrue(ready.wait(5))
            try:
                renderer.RUN.acquire()
                try:
                    with patch.object(renderer,'run_preview_render') as render:
                        self.assertEqual(post()[0],409)
                        render.assert_not_called()
                finally:
                    renderer.RUN.release()
                with patch.object(renderer,'run_preview_render',return_value='preview.mp4'):
                    self.assertEqual(post()[0],200)
                self.assertTrue(renderer.RUN.acquire(timeout=5))
                renderer.RUN.release()
                with patch.object(renderer,'run_preview_render',side_effect=RuntimeError('failure')):
                    self.assertEqual(post()[0],500)
                self.assertTrue(renderer.RUN.acquire(timeout=5))
                renderer.RUN.release()
            finally:
                servers[0].shutdown();servers[0].server_close();worker.join(5)

    def test_broadcast_encoding_arguments_unchanged(self):
        with patch.object(renderer,'run_ffmpeg_progress') as run:
            renderer.encode('frames_synthe3','test',250,skip_preview=True)
        cmd=run.call_args.args[0]
        self.assertIn('tinterlace=mode=interleave_top',cmd[cmd.index('-vf')+1])
        for key,value in [('-framerate','50'),('-c:v','qtrle'),('-pix_fmt','rgba'),('-field_order','tt')]:
            self.assertEqual(cmd[cmd.index(key)+1],value)

    def test_python_and_inline_javascript_syntax(self):
        for path in ROOT.glob('*.py'): ast.parse(path.read_text())
        for path in ROOT.glob('*.html'):
            for script in re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',path.read_text(),re.S):
                if script.strip(): subprocess.run(['node','--check'],input=script,text=True,check=True,capture_output=True)


if __name__ == '__main__':
    unittest.main()
