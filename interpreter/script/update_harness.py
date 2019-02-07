#!/usr/bin/env python

from __future__ import print_function
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
HARNESS_JS = os.path.join(SCRIPT_DIR, 'harness.js')
HARNESS_ML = os.path.join(SCRIPT_DIR, 'harness.ml')

def Escape(s):
  return re.sub(r'([\\"])', r'\\\1', s)

if __name__ == '__main__':
  output = []
  with open(HARNESS_JS) as harness_js:
    for line in harness_js:
      output.append('  \"{}\\n\"'.format(Escape(line.rstrip())))

  output_str = 'let harness =\n{}\n'.format(' ^\n'.join(output))

  with open(HARNESS_ML, 'w') as harness_ml:
    harness_ml.write(output_str)
