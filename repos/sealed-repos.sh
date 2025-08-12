#!/bin/bash

# Title: ArgoCD Repo Secrets to SealedSecrets Converter (Robust Version)
# Description: Safely converts ArgoCD repository secrets to SealedSecrets
# Requirements: kubectl, kubeseal

set -eo pipefail

# Configuration
OUTPUT_DIR="argocd-sealed-secrets"
NAMESPACE="argocd"
SECRET_LABEL="argocd.argoproj.io/secret-type=repository"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🔍 Fetching ArgoCD repository secrets..."
kubectl get secrets -n "$NAMESPACE" -l "$SECRET_LABEL" -o name | while read -r secret; do
    # Extract secret name
    SECRET_NAME=${secret#*/}
    
    # Skip if already a SealedSecret
    if [[ "$SECRET_NAME" == *"sealed"* ]]; then
        echo "⏩ Skipping already sealed secret: $SECRET_NAME"
        continue
    fi
    
    # Generate new name
    NEW_NAME="sealed-$SECRET_NAME"
    
    echo "🔧 Processing: $SECRET_NAME -> $NEW_NAME"
    
    # Create temporary working file
    TEMP_FILE=$(mktemp)
    
    # Get secret and convert to SealedSecret
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | \
    jq --arg new_name "$NEW_NAME" '
    {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": $new_name,
            "namespace": "'"$NAMESPACE"'",
            "labels": .metadata.labels,
            "annotations": (.metadata.annotations + {"original-secret-name": .metadata.name})
        },
        "type": .type,
        "data": .data
    }' > "$TEMP_FILE"
    
    # Convert to SealedSecret
    OUTPUT_FILE="$OUTPUT_DIR/$NEW_NAME.yaml"
    kubeseal -o yaml < "$TEMP_FILE" > "$OUTPUT_FILE"
    
    # Clean up
    rm "$TEMP_FILE"
    
    echo "✅ Created: $OUTPUT_FILE"
done

echo "✨ Conversion complete! SealedSecrets saved to: $OUTPUT_DIR"
echo "💾 Remember to:"
echo "  1. Review the generated files"
echo "  2. Commit them to your GitOps repository"
echo "  3. Apply with: kubectl apply -f $OUTPUT_DIR/"
