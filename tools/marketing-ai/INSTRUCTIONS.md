# Using the SAS Open Source Project Starter Kit

Use the SAS Open Source Project Starter Kit to seed a GitHub repository for a new open source project that follows the [SAS Open Source Contributions](https://inside.sas.com/policies/open-source-contributions/) policy.

See [First-Party Open Source Contributions](https://rndconfluence.sas.com/x/8TvSFg) for a complete guide to using this kit.

## How to Use This Kit

1. Navigate to `https://github.com/organizations/sas-institute-rnd-internal/repositories/new`.
1. Click the __Repository template__ drop-down menu.
1. Select `sas-institute-rnd-internal/workflows-sas-open-source-project-starter-kit` as your new project's template.
1. Enter a project name that begins with `tmp-`.
1. Enter a description for the project.
1. Select a visibility level for the project.
1. Click __Create repository__.

> [!NOTE]
> If you do not select the `Internal` visibility setting, you must specifically provide reviewers access to your repository at a later date.

GitHub uses the SAS Open Source Project Starter Kit to create a new repository for your work, pre-populating that repository with all of the kit's materials.

## Preparing Your Project for Review

Members of the Open Source Program Office and additional subject matter experts will review your project prior to release.
Files in the starter kit are annotated with comments to assist you in preparing and staging your project.
Follow these instructions to ensure efficient and timely review.

For complete instructions, see the Open Source Program Office's guide to creating [First-Party Open Source Contributions](https://rndconfluence.sas.com/x/8TvSFg).

> [!TIP]
> Delete the INSTRUCTIONS.md file from your project before submitting your project for review.

To submit your open source project for review, follow the [Open Source Contributions Quick Start Guide](https://rndconfluence.sas.com/x/sKjrFg).
You provide links to your project and its materials as part of this review.

## Creating Project Documentation

The SAS Open Source Project Starter Kit contains resources for building project documentation that complies with SAS brand standards. This documentation is built and served with the [Docusaurus](https://docusaurus.io/) website generator.

**If you want to use these documentation materials,** edit the `website/docusaurus.config.ts` file in order to:

- replace `<projectName>` with your project name
- replace `<your logo>` with the file name of your project logo

> [!NOTE]
> The `docusaurus.config.ts` file contains multiple instances of these variables; be sure to locate and change them all.

Add Markdown files to `website/docs` to begin creating project documentation.
The website is automatically rebuilt when changes to these files are merged to the `main` branch.
See its [README](./website/README.md) for details.

See project documentation for the [SAS extension for Visual Studio Code](https://github.com/sassoftware/vscode-sas-extension/tree/main/website) for an example.

**If you do not wish to use these documentation materials,** remove the following components from the repository:

- the `website` directory and all files that it contains
- the `Update Documentation` section in the `CONTRIBUTING.md` file
- `.github/dependabot.yml`
- `.github/workflows/deploy-doc.yml`
