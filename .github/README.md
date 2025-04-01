# GitHub Actions CI/CD Setup for BizBlasts

This document outlines how to configure the CI/CD pipeline for the BizBlasts Rails application.

## CI/CD Pipeline

The GitHub Actions workflow in this repository provides:

1. **Security Scanning**: Checks Ruby code and JavaScript dependencies for vulnerabilities
2. **Code Linting**: Ensures code meets style guidelines using RuboCop
3. **Automated Testing**: Runs unit and system tests
4. **Automated Deployment**: Deploys to Render when changes are pushed to the main branch

## Configuration Steps

### 1. Configure Render API Key

To enable automated deployments to Render, you need to add your Render API key as a GitHub secret:

1. Log in to your Render dashboard at https://dashboard.render.com/
2. Go to Account Settings → API Keys
3. Generate a new API key with an appropriate description (e.g., "GitHub Actions Deployment")
4. Copy the generated API key

Then add it to your GitHub repository:

1. Go to your GitHub repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `RENDER_API_KEY`
4. Value: (paste your Render API key)
5. Click "Add secret"

### 2. Get Your Render Service ID

The deployment script uses the Render service ID, which is set to `srv-cvlj0jfgi27c73e3u680` in the CI workflow. This is the unique identifier for your Render web service. If your service ID changes:

1. In your Render dashboard, click on your web service
2. Look at the URL, which should be in the format `https://dashboard.render.com/web/srv-XXXXX`
3. The `srv-XXXXX` part is your service ID
4. If your service ID is different, update it in the `.github/workflows/ci.yml` file

### 3. Enabling/Disabling Automatic Deployment

The automatic deployment is configured to run only on pushes to the `main` branch. If you want to disable automatic deployment temporarily:

1. Comment out the `deploy` job in the `.github/workflows/ci.yml` file
2. Or, push to branches other than `main` to avoid triggering deployments

## Manual Workflow Runs

You can also manually trigger the workflow:

1. Go to the "Actions" tab in your GitHub repository
2. Select the "CI" workflow
3. Click "Run workflow"
4. Select the branch to run the workflow from
5. Click "Run workflow"

## Troubleshooting

If you encounter issues with the deployment:

1. Check the GitHub Actions logs for error messages
2. Verify your Render API key is correct and has the necessary permissions
3. Ensure your Render service ID is correct
4. Check that your Render account has sufficient resources available 