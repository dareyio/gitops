#!/bin/bash
# Generate SSH keypair for ArgoCD repository access
# Keys stored in gitops/.ssh/ (gitignored)

set -e

echo "🔐 Setting up ArgoCD Deploy Keys..."
echo ""

# Create directory if it doesn't exist
mkdir -p gitops/.ssh
chmod 700 gitops/.ssh

# Generate SSH keypair
ssh-keygen -t ed25519 -C "argocd-deploy-key" -f gitops/.ssh/argocd-deploy-key -N ""

echo ""
echo "✅ SSH keypair generated successfully!"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📋 NEXT STEPS:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Add PUBLIC key to GitHub as Deploy Key:"
echo "   - Go to: https://github.com/dareyio/terraform/settings/keys"
echo "   - Click 'Add deploy key'"
echo "   - Title: 'ArgoCD Deploy Key'"
echo "   - Key: (copy the public key below)"
echo "   - ⚠️  Do NOT check 'Allow write access' (read-only)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "PUBLIC KEY (copy this):"
echo "═══════════════════════════════════════════════════════════════"
cat gitops/.ssh/argocd-deploy-key.pub
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "2️⃣  Add PRIVATE key to GitHub Secrets:"
echo "   - Go to: https://github.com/dareyio/terraform/settings/secrets/actions"
echo "   - Click 'New repository secret'"
echo "   - Name: ARGOCD_SSH_PRIVATE_KEY"
echo "   - Value: (copy the private key from the command below)"
echo ""
echo "   Run this command to copy private key:"
echo "   cat gitops/.ssh/argocd-deploy-key | pbcopy    # macOS"
echo "   cat gitops/.ssh/argocd-deploy-key | xclip     # Linux"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  SECURITY NOTES:"
echo "   - Keys are stored in gitops/.ssh/ (gitignored)"
echo "   - NEVER commit these keys to git"
echo "   - Private key location: gitops/.ssh/argocd-deploy-key"
echo "   - Public key location: gitops/.ssh/argocd-deploy-key.pub"
echo ""
echo "✅ Setup complete!"

