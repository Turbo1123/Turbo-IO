import copy
from xml.etree import ElementTree
from turbo_dashboard.contracts import TEMPLATES
from turbo_dashboard.preview import render
from test_app_package import example


def test_preview_escapes_content():
    card = copy.deepcopy(TEMPLATES[0])
    card['components'][0]['text'] = '<script>x&y</script>'
    svg = render(card)
    root = ElementTree.fromstring(svg)
    assert not root.findall('.//{http://www.w3.org/2000/svg}script')
    assert '&lt;script&gt;' in svg
    assert root.attrib['width'] == '256'
    assert ElementTree.fromstring(render(example(), 'home')).attrib['width'] == '540'
