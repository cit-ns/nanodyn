# Copyright (C) 2019 The ESPResSo project
#
# This file is part of ESPResSo.
#
# ESPResSo is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ESPResSo is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import re
import os
import io
import sys
import ast
import tokenize
import unittest
import importlib
import espressomd
from unittest.mock import MagicMock


def _id(x):
    return x


# global variable: if one import failed, all subsequent imports will be skipped,
# see skip_future_imports_dependency()
skip_future_imports = False


def configure_and_import(filepath,
                         gpu=False,
                         substitutions=lambda x: x,
                         cmd_arguments=None,
                         script_suffix=None,
                         move_to_script_dir=True,
                         random_seeds=True,
                         mock_visualizers=True,
                         **parameters):
    """
    Copy a Python script to a new location and alter some lines of code:

    - change global variables and local variables (up to 1 indentation level)
    - pass command line arguments during import to emulate shell execution
    - disable the OpenGL/Mayavi modules if they are not compiled
    - disable the matplotlib GUI using a text-based backend
    - use random seeds for the RNG in NumPy and ESPResSo
    - temporarily move to the directory where the script is located

    Parameters
    ----------
    filepath : str
        python script to import
    gpu : bool
        whether GPU is necessary or not
    substitutions : function
        custom text replacement operation (useful to edit out calls to the
        OpenGL or Mayavi visualizers' ``run()`` method)
    cmd_arguments : list
        command line arguments, i.e. sys.argv without the script path
    script_suffix : str
        suffix to append to the configured script (useful when a single
        module is being tested by multiple tests in parallel)
    random_seeds : bool
        if ``True``, use random seeds in RNGs
    mock_visualizers : bool
        if ``True``, substitute ES visualizers with `Mock()` classes in case
        of `ImportError()` (use ``False`` if an `ImportError()` is relevant
        to your test)
    move_to_script_dir : bool
        if ``True``, move to the script's directory (useful when the script
        needs to load files hardcoded as relative paths, or when files are
        generated and need cleanup); this is enabled by default
    \*\*parameters :
        global variables to replace

    """
    if skip_future_imports:
        module = MagicMock()
        skipIfMissingImport = skip_future_imports_dependency(filepath)
        return module, skipIfMissingImport
    if gpu and not espressomd.gpu_available():
        skip_future_imports_dependency(filepath)
        skipIfMissingGPU = unittest.skip("gpu not available, skipping test!")
        module = MagicMock()
        return module, skipIfMissingGPU
    filepath = os.path.abspath(filepath)
    # load original script
    # read in binary mode, then decode as UTF-8 to avoid this python3.5 error:
    # UnicodeDecodeError: 'ascii' codec can't decode byte 0xc3 in position 915:
    #                      ordinal not in range(128)
    with open(filepath, "rb") as f:
        code = f.read().decode(encoding="utf-8")
    # custom substitutions
    code = substitutions(code)
    assert code.strip()
    # substitute global variables
    code = substitute_variable_values(code, **parameters)
    # substitute command line arguments
    if cmd_arguments is not None:
        code, old_sys_argv = set_cmd(code, filepath, cmd_arguments)
    # disable matplotlib GUI using the Agg backend
    code = disable_matplotlib_gui(code)
    # disable OpenGL/Mayavi GUI using MagicMock()
    if mock_visualizers:
        code = mock_es_visualization(code)
    # use random seeds for ES and NumPy RNGs
    if random_seeds:
        code = set_random_seeds(code)
    # save changes to a new file
    if script_suffix:
        if script_suffix[0] != "_":
            script_suffix = "_" + script_suffix
    else:
        script_suffix = ""
    script_suffix += "_processed.py"
    output_filepath = os.path.splitext(filepath)[0] + script_suffix
    assert os.path.isfile(output_filepath) is False, \
        "File {} already processed, cannot overwrite".format(output_filepath)
    with open(output_filepath, "wb") as f:
        f.write(code.encode(encoding="utf-8"))
    # import
    dirname, basename = os.path.split(output_filepath)
    if move_to_script_dir:
        os.chdir(dirname)
    sys.path.insert(0, dirname)
    module_name = os.path.splitext(basename)[0]
    try:
        module = importlib.import_module(module_name)
    except espressomd.FeaturesError as err:
        skip_future_imports_dependency(filepath)
        skipIfMissingFeatures = unittest.skip(str(err) + ", skipping test!")
        module = MagicMock()
    else:
        skipIfMissingFeatures = _id
    if cmd_arguments is not None:
        # restore original command line arguments
        sys.argv = old_sys_argv
    return module, skipIfMissingFeatures


def set_cmd(code, filepath, cmd_arguments):
    assert isinstance(cmd_arguments, (list, tuple))
    sys_argv = list(map(str, cmd_arguments))
    sys_argv.insert(0, os.path.basename(filepath))
    re_import_sys = re.compile("^import[\t\ ]+sys[\t\ ]*$", re.M)
    re_import_argparse = re.compile("^import[\t\ ]+argparse[\t\ ]*$", re.M)
    if re_import_sys.search(code) is not None:
        code = re_import_sys.sub("\g<0>\nsys.argv = " + str(sys_argv), code, 1)
    elif re_import_argparse.search(code) is not None:
        code = re_import_argparse.sub("\g<0>\nimport sys\nsys.argv = "
                                      + str(sys_argv), code, 1)
    else:
        raise AssertionError("module sys (or argparse) is not imported")
    old_sys_argv = list(sys.argv)
    return code, old_sys_argv


def substitute_variable_values(code, strings_as_is=False, keep_original=True,
                               **parameters):
    """
    Substitute values of global variables.

    Parameters
    ----------
    code : str
        Source code to edit.
    strings_as_is : bool
        If ``True``, consider all values in \*\*parameters are strings and
        substitute them in-place without formatting by ``repr()``.
    keep_original : bool
        Keep the original value (e.g. ``N = 10; _N__original = 1000``), helps
        with debugging. If ``False``, make sure the original value is not a
        multiline statement, because removing its first line would lead to
        a syntax error.
    \*\*parameters :
        Variable names and their new value.

    """
    for variable, value in parameters.items():
        assert variable in code, "variable {} not found".format(variable)
        re_var = re.compile("^(\t|\ {,4})(" + variable + ")(?= *=[^=])", re.M)
        assert re_var.search(code) is not None, \
            "variable {} has no assignment".format(variable)
        val = strings_as_is and value or repr(value)
        code = re_var.sub(r"\g<1>\g<2> = " + val + r"; _\g<2>__original", code)
        if not keep_original:
            code = re.sub(r"; _" + variable + "__original.+", "", code)
    return code


def set_random_seeds(code):
    # delete explicit ESPResSo seed
    aliases = re.findall(r"([^\s;]+) *= *(?:espressomd\.)?System *\(", code)
    pattern = r"(?<=[\s;]){}\.(?:seed|random_number_generator_state)(?= *=[^=])"
    subst = "{}.set_random_state_PRNG(); _random_seed_es__original"
    for varname in set(aliases):
        code = re.sub(pattern.format(varname), subst.format(varname), code)
    # delete explicit NumPy seed
    code = re.sub(r"(?<=[\s;])(?:numpy|np)\.random\.seed *(?=\()",
                  "_random_seed_np = (lambda *args, **kwargs: None)", code)
    return code


def delimit_statements(code):
    """
    For every Python statement, map the line number where it starts to the
    line number where it ends.
    """
    statements = []
    statement_start = None
    for tok in tokenize.tokenize(io.BytesIO(code.encode("utf-8")).readline):
        if tok.exact_type == tokenize.ENDMARKER:
            break
        elif tok.exact_type == tokenize.ENCODING:
            pass
        elif tok.start == tok.end:
            pass
        elif tok.exact_type == tokenize.NEWLINE or tok.exact_type == tokenize.NL and prev_tok.exact_type == tokenize.COMMENT:
            statements.append((statement_start, tok.start[0]))
            statement_start = None
        elif tok.exact_type == tokenize.NL:
            pass
        elif statement_start is None:
            statement_start = tok.start[0]
        prev_tok = tok
    return dict(statements)


def protect_ipython_magics(code):
    return re.sub("^(%+)(?=[a-z])", "#_IPYTHON_MAGIC_\g<1>", code, flags=re.M)


def deprotect_ipython_magics(code):
    return re.sub("^#_IPYTHON_MAGIC_(%+)(?=[a-z])", "\g<1>", code, flags=re.M)


class GetMatplotlibImports(ast.NodeVisitor):
    """
    Find all line numbers where ``matplotlib`` is imported.
    """

    def __init__(self):
        self.matplotlib_first = None
        self.matplotlib_aliases = []
        self.pyplot_aliases = []

    def visit_Import(self, node):
        # get line number of the first matplotlib import
        for child in node.names:
            if child.name.split(".")[0] == "matplotlib":
                self.matplotlib_first = self.matplotlib_first or node.lineno
        # get matplotlib aliases
        for child in node.names:
            if child.name == "matplotlib":
                self.matplotlib_aliases.append(child.asname or child.name)
        # get pyplot aliases
        for child in node.names:
            if child.name == "matplotlib.pyplot":
                self.pyplot_aliases.append(child.asname or child.name)
            elif child.name == "matplotlib":
                name = (child.asname or "matplotlib") + ".pyplot"
                self.pyplot_aliases.append(name)

    def visit_ImportFrom(self, node):
        # get line number of the first matplotlib import
        if node.module.split(".")[0] == "matplotlib":
            self.matplotlib_first = self.matplotlib_first or node.lineno
        # get pyplot aliases
        for child in node.names:
            if node.module == "matplotlib" and child.name == "pyplot":
                self.pyplot_aliases.append(child.asname or child.name)


def disable_matplotlib_gui(code):
    """
    Use the matplotlib Agg backend (no GUI).
    """
    visitor = GetMatplotlibImports()
    visitor.visit(ast.parse(protect_ipython_magics(code)))
    # find under which names matplotlib is accessible
    aliases_mpl = set(visitor.matplotlib_aliases)
    # find under which names pyplot is accessible
    aliases_plt = set(visitor.pyplot_aliases)
    # remove any custom backend
    for alias in aliases_mpl:
        code = re.sub(r"^[\t\ ]*" + alias + r"\.use\(([\"']+).+?\1[\t\ ]*\)",
                      "", code, flags=re.M)
    # use the Agg backend
    code = re.sub(r"^([\t\ ]*)(?=(?:from|import)[\t\ ]+matplotlib[\.\s])",
                  r"\g<1>import matplotlib as _mpl;_mpl.use('Agg');",
                  code, 1, re.M)
    # remove interactive mode
    for alias in aliases_plt:
        code = re.sub(r"((?:^[\t\ ]*|;)" + alias + r")\.ion\(",
                      "\g<1>.ioff(", code, flags=re.M)
    # remove magic function
    code = re.sub(r"^get_ipython.*", "", code, flags=re.M)
    return code


class GetEspressomdVisualizerImports(ast.NodeVisitor):
    """
    Find line numbers and aliases of imported ESPResSo visualizers.
    """

    def __init__(self):
        self.visualizers = {
            "visualization",
            "visualization_opengl",
            "visualization_mayavi"}
        self.namespace_visualizers = {
            "espressomd." + x for x in self.visualizers}
        self.visu_aliases = []
        self.visu_linenos = []

    def visit_Import(self, node):
        # get visualizer alias
        for child in node.names:
            if child.name in self.namespace_visualizers:
                self.visu_aliases.append(child.asname or child.name)
                self.visu_linenos.append(node.lineno)

    def visit_ImportFrom(self, node):
        if node.module in self.namespace_visualizers:
            for child in node.names:
                if child.name == "*":
                    raise ValueError("cannot use MagicMock() on a wildcard "
                                     "import at line {}".format(node.lineno))
                elif child.name in {"openGLLive", "mayaviLive"}:
                    self.visu_aliases.append(child.asname or child.name)
                    self.visu_linenos.append(node.lineno)
        # get visualizer alias
        if node.module == "espressomd":
            for child in node.names:
                if child.name in self.visualizers:
                    self.visu_aliases.append(child.asname or child.name)
                    self.visu_linenos.append(node.lineno)


def mock_es_visualization(code):
    """
    Replace ``import espressomd.visualization_<backend>`` by a ``MagicMock()``
    when the visualization module is unavailable, by catching the
    ``ImportError()`` exception. Please note that ``espressomd.visualization``
    is deferring the exception, thus requiring additional checks.

    Import aliases are supported, however please don't use
    ``from espressomd.visualization import *`` because it hides the namespace
    of classes to be mocked.
    """
    # replacement template
    r_es_vis_mock = r"""
try:
    {0}{1}
except ImportError:
    from unittest.mock import MagicMock
    import espressomd
    {2} = MagicMock()
""".lstrip()

    def check_for_deferred_ImportError(line, alias):
        if "_opengl" not in line and "_mayavi" not in line:
            if "openGLLive" in line or "mayaviLive" in line:
                return """
    if hasattr({0}, 'deferred_ImportError'):
        raise {0}.deferred_ImportError""".format(alias)
            else:
                return """
    if hasattr({0}.mayaviLive, 'deferred_ImportError') or \\
       hasattr({0}.openGLLive, 'deferred_ImportError'):
        raise ImportError()""".format(alias)
        else:
            return ""

    visitor = GetEspressomdVisualizerImports()
    visitor.visit(ast.parse(protect_ipython_magics(code)))
    lines = code.split("\n")
    for alias, lineno in zip(visitor.visu_aliases, visitor.visu_linenos):
        line = lines[lineno - 1]
        checks = check_for_deferred_ImportError(line, alias)
        lines[lineno - 1] = r_es_vis_mock.format(line, checks, alias)

    return "\n".join(lines)


def skip_future_imports_dependency(filepath):
    """
    If an import failed, all subsequent imports will be skipped. The
    fixture message provides the name of the module that failed.
    """
    global skip_future_imports
    if not skip_future_imports:
        module_name = os.path.splitext(os.path.basename(filepath))[0]
        assert module_name != ""
        skip_future_imports = module_name
    return unittest.skip("failed to import {}, skipping test!"
                         .format(skip_future_imports))
