#!/bin/bash

# ═══════════════════════════════════════════════════
#  Farmacias Aragón Wallet — Deploy a main
#  Doble clic para hacer push automático a GitHub
# ═══════════════════════════════════════════════════

# Ir a la carpeta del proyecto (misma carpeta que este script)
cd "$(dirname "$0")"

echo ""
echo "⚕️  Farmacias Aragón Wallet — Deploy"
echo "────────────────────────────────────"
echo ""

# Verificar que es un repo git
if [ ! -d ".git" ]; then
  echo "❌ Esta carpeta no es un repositorio Git."
  echo "   Inicializa el repo primero con: git init"
  echo ""
  read -p "Presiona Enter para cerrar..."
  exit 1
fi

# Mostrar archivos modificados
echo "📁 Archivos con cambios:"
git status --short
echo ""

# Pedir mensaje de commit
read -p "✏️  Mensaje de commit (Enter para usar 'update'): " MSG
COMMIT_MSG="${MSG:-update}"

echo ""
echo "🚀 Subiendo cambios..."
echo ""

# Git add, commit y push
git add .
git commit -m "$COMMIT_MSG"
git push origin main

echo ""
if [ $? -eq 0 ]; then
  echo "✅ Deploy exitoso. Netlify actualizará el sitio en ~30 segundos."
else
  echo "⚠️  Hubo un error. Revisa la conexión o las credenciales de GitHub."
fi

echo ""
read -p "Presiona Enter para cerrar..."
