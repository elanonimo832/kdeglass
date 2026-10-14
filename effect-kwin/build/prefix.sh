export PATH=/home/jracosta/.local/bin:$PATH

# LD_LIBRARY_PATH only needed if you are building without rpath
# export LD_LIBRARY_PATH=/home/jracosta/.local/lib:$LD_LIBRARY_PATH

export XDG_DATA_DIRS=/home/jracosta/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
export XDG_CONFIG_DIRS=/home/jracosta/.local/etc/xdg:${XDG_CONFIG_DIRS:-/etc/xdg}

export QT_PLUGIN_PATH=/home/jracosta/.local/lib/plugins:$QT_PLUGIN_PATH
export QML2_IMPORT_PATH=/home/jracosta/.local/lib/qml:$QML2_IMPORT_PATH

export QT_QUICK_CONTROLS_STYLE_PATH=/home/jracosta/.local/lib/qml/QtQuick/Controls.2/:$QT_QUICK_CONTROLS_STYLE_PATH

export MANPATH=/home/jracosta/.local/share/man:${MANPATH:-/usr/local/share/man:/usr/share/man}

export SASL_PATH=/home/jracosta/.local/lib/sasl2:${SASL_PATH:-/usr/lib/sasl2}

export PYTHONPATH="/home/jracosta/.local/lib/python3.14/site-packages":$PYTHONPATH
