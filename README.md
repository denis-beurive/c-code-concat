# Description

This script can be used to "concatenate" C sources.

> **DISCLAIMER**: Please note that, technically speaking, there is absolutely no good reason to concatenate C sources... quite the contrary. The objective of software engineering is to decouple the functional elements that make up the software. The advantages of functional decoupling are not debatable and are universally known and recognized. When you concatenate the sources, you increase noticeably the coupling level of your code base, which leads to numerous bad well-known consequences.

# Usage

Usage:

```bash
perl finder.pl [--verbose] \
               [--src=<directory path> [--src=<directory path>]...] \
               [--reject-dir=<directory path> [--reject-dir=<directory path>]...] \
               [--dest=<directory path>]
```

Example:

```bash
perl finder.pl --verbose --src=./src --reject-dir=./src/examples --reject-dir=./src/tests --dest=/tmp
```

> Please note that the option `--src` may appear multiple times (if your sources are kept under multiple directories).

Concatenate all C files (`.c` and `.h`) under the directory `./src`, with the exception of the files under `./src/examples` and `./src/tests`. Write the 2 resulting files (`concat.c` and `concat.h`) into the directory `/tmp`.

In order for the script to work, it needs to know the following information:
* the order in which the header files must be concatenated.
* the list of header files that must be included into the target header file (`concat.h`). The other header files will be included at the beginning of the target C file (`concat.c`).

Header files that must be included in the target header file (`concat.h`) must begin with the string:

```c
// EXPOSE <rank number>
```

With `<rank number>` = `1`, `2`, `3`...

* The header file with the rank 1 will be included first.
* The header file with the rank 2 will be included second.
* ... and so on.

> Please note that you can also use the ranks 2, 4, 6... It does not matter. The header file with the rank 2 will be included first. The header file with the rank 4 will be included second....

All other header files will be included in the target C file (`concat.c`). But these files may be included following an order (some headers depend on others). In order to define an inclusion order between the header files that will be included into the target C file (`concat.c`), we add the comment `// RANK=<rank number>` at the beginning of a file (With `<rank number>` = `1`, `2`, `3`...).








