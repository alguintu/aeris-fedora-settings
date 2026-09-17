#!/usr/bin/env python3
"""Convert Quickshell's vendored SVGs with Android's own SVG importer.

Run after Gradle has resolved the Android build tools. Uses JAVA_HOME or java.
No downloaded art, rasterization, or runtime SVG dependency.
"""
from pathlib import Path
import os
import copy
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

mobile = Path(__file__).resolve().parents[1]
source = mobile.parent / 'quickshell/aeris-dashboard/assets'
output = mobile / 'app/src/main/res/drawable'
icons = {
    'aeris_mark': 'custom/aeris', 'aeris_wordmark': 'custom/aeris-wordmark',
    'moon': 'feather/moon', 'sun': 'feather/sun', 'power': 'feather/power',
    'lights_off': 'icons/lightbulb-off-outline', 'party': 'icons/star-four-points',
    'fan': 'icons/fan', 'wind': 'feather/wind', 'zap': 'feather/zap',
    'chip': 'feather/cpu', 'coffee': 'feather/coffee', 'monitor': 'feather/monitor',
    'processor': 'icons/memory', 'graphics_card': 'icons/expansion-card',
    'play': 'icons/play', 'pause': 'icons/pause', 'skip_forward': 'icons/skip-next',
    'rotate_ccw': 'feather/rotate-ccw',
    'chevron_down': 'feather/chevron-down', 'connection': 'feather/globe',
}
cache = Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle')) / 'caches/modules-2/files-2.1'
jars = []
for group, artifact in [('com.android.tools', 'sdk-common'), ('com.android.tools', 'common'),
                        ('com.google.guava', 'guava'), ('org.jetbrains.kotlin', 'kotlin-stdlib')]:
    versions = sorted((cache/group/artifact).glob('*'), key=lambda p: tuple(int(s) if s.isdigit() else 0 for s in p.name.replace('-', '.').split('.')))
    if not versions:
        raise SystemExit('Run ./gradlew :app:assembleDebug first to resolve Android tools.')
    jars.extend(versions[-1].rglob('*.jar'))
java = str(Path(os.environ['JAVA_HOME'])/'bin/java') if 'JAVA_HOME' in os.environ else 'java'
with tempfile.TemporaryDirectory() as tmp:
    runner = Path(tmp)/'ImportIcons.java'
    runner.write_text('''import java.nio.file.*;
import com.android.ide.common.vectordrawable.Svg2Vector;
class ImportIcons {
 public static void main(String[] args) throws Exception {
  for (int i=0; i<args.length; i+=2) {
   try (var out=Files.newOutputStream(Path.of(args[i+1]))) {
    String error=Svg2Vector.parseSvgToXml(Path.of(args[i]),out);
    if (!error.isBlank()) throw new IllegalStateException(args[i]+": "+error);
   }
  }
 }
}
''')
    args = [arg for name, asset in icons.items() for arg in (str(source/(asset+'.svg')), str(output/('ic_'+name+'.xml')))]
    subprocess.run([java, '-cp', os.pathsep.join(map(str,jars)), str(runner), *args], check=True)
licenses = mobile/'app/src/main/assets/licenses'
licenses.mkdir(parents=True, exist_ok=True)
for folder, name in [('feather','Feather-MIT.txt'),('icons','Material-Design-Icons-Apache-2.0.txt')]:
    shutil.copyfile(source/folder/'LICENSE.txt',licenses/name)
# Center the same mark inside Android's adaptive-icon safe area.
android = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', android)
a = lambda name: '{'+android+'}'+name
mark = ET.parse(output/'ic_aeris_mark.xml').getroot()
root = ET.Element('vector', {a('width'):'108dp',a('height'):'108dp',a('viewportWidth'):'108',a('viewportHeight'):'108'})
group = ET.SubElement(root,'group',{a('translateX'):'24',a('translateY'):'26',a('scaleX'):'0.68',a('scaleY'):'0.68'})
for child in mark:
    shape = copy.deepcopy(child)
    for path in shape.iter('path'):
        path.set(a('fillColor'),'#88C0D0')
    group.append(shape)
ET.indent(root)
ET.ElementTree(root).write(output/'ic_aeris_foreground.xml',encoding='unicode',xml_declaration=True)
print(f'Imported {len(icons)} dashboard vectors, launcher artwork, and licenses.')
