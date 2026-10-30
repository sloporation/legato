cd qt
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build
if [ "$(uname)" = Darwin ]; then
    open build/Legato.app
else
    ./build/legato
fi
