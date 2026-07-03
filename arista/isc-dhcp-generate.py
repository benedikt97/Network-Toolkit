import os
import sys
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader('.'))
template = env.get_template(sys.argv[1])
rendered_output = template.render(**os.environ)
print(rendered_output)