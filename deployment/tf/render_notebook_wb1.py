#!/usr/bin/env python3
"""Rellena placeholders en notebook-wb1.yaml (salida en TMP del env)."""
import os
import pathlib


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    p = pathlib.Path(os.environ["TEMPLATE"])
    t = p.read_text()
    t = t.replace("__WORKBENCH_IMAGE__", os.environ["WB_IMAGE"])
    t = t.replace("__IMAGE_STREAM_TAG__", os.environ["ISTAG_FOR_ANN"])
    t = t.replace("__IMAGE_DISPLAY_NAME__", os.environ["DISP_NAME"])
    t = t.replace("__OPENSHIFT_USER__", os.environ["OPENSHIFT_USER"])

    gc = (os.environ.get("GIT_COMMIT") or "").strip()
    if gc:
        t = t.replace(
            "__GIT_COMMIT_ANNOTATION__",
            'notebooks.opendatahub.io/last-image-version-git-commit-selection: "%s"' % esc(gc),
        )
    else:
        t = t.replace("__GIT_COMMIT_ANNOTATION__", "")

    hw_rv = (os.environ.get("HW_RV") or "").strip()
    hw_name = (os.environ.get("WORKBENCH_HW_PROFILE") or "").strip()
    ns = os.environ.get("NOTEBOOK_IS_NS", "redhat-ods-applications")
    if hw_rv and hw_name:
        hw_block = (
            'opendatahub.io/hardware-profile-name: "%s"\n'
            '    opendatahub.io/hardware-profile-namespace: "%s"\n'
            '    opendatahub.io/hardware-profile-resource-version: "%s"'
        ) % (esc(hw_name), esc(ns), esc(hw_rv))
        t = t.replace("__HARDWARE_PROFILE_ANNOTATIONS__", hw_block)
    else:
        t = t.replace("__HARDWARE_PROFILE_ANNOTATIONS__", "")

    pathlib.Path(os.environ["TMP"]).write_text(t)


if __name__ == "__main__":
    main()
