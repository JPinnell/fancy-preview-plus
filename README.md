# Fancy Preview Plus

A Perl script that enhances LaTeX documents by automatically generating interactive, on-hover tooltips for citations, figures, equations, and more.

This script orchestrates a multi-pass compilation of a LaTeX source file to produce a self-contained, interactive PDF. It is a heavily modified and debugged version of the original `fancy-preview` script by Robert Marik.

## Features

* **Interactive Tooltips:** Creates on-hover popup previews for document elements.
* **Broad Support:** Generates tooltips for:
    * **Citations:** Shows the full bibliographic entry on hover (requires `biblatex`).
    * **Figures & Tables:** Displays the full figure or table.
    * **Equations:** Shows the rendered equation.
    * **Theorem-like Environments:** Supports `theorem`, `lemma`, `definition`, etc.
* **Selective Generation:** Use the `--types` flag to specify exactly which tooltips you want to build (e.g., just citations).
* **Customizable:** Easily change the tooltip's background color, border color, and content scale by editing variables at the top of the script.

## Requirements

To use this script, you will need:
* A working **Perl** installation.
* A **LaTeX distribution** (like TeX Live, MiKTeX).
* The `biber` command for `biblatex` support.
* The `pdfcrop` utility (usually included with TeX Live).
* The following LaTeX packages installed: `fancytooltips`, `preview`, `biblatex`, `tikz`, `hyperref`.

## Usage

The script is designed to be the **only** command you need to run. It handles the full `pdflatex -> biber -> pdflatex -> ...` cycle.

### 1. Best Practice: Start Clean

For the most reliable results, always delete all temporary LaTeX files before running the script.

**On Windows (Command Prompt):**
```cmd
del /f /q *.aux *.bbl *.bcf *.blg *.log *.out *.run.xml *.tmp *-crop.pdf minimal.*
