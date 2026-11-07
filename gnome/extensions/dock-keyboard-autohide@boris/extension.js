import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const DOCK_SCHEMA = 'org.gnome.shell.extensions.dash-to-dock';
const DOCK_NAME = 'dashtodockContainer';
const LEAVE_DELAY_MS = 300;

export default class DockKeyboardAutohide extends Extension {
    enable() {
        this._settings = new Gio.Settings({schema_id: DOCK_SCHEMA});
        this._inDock = false;
        this._checkId = 0;
        this._timeoutId = 0;
        this._focusId = global.stage.connect('notify::key-focus', () => this._onKeyFocus());
    }

    disable() {
        if (this._focusId)
            global.stage.disconnect(this._focusId);
        this._focusId = 0;
        this._cancelCheck();
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
            this._settings.set_boolean('intellihide', this._savedValue);
        }
        this._settings = null;
    }

    _isInDock(actor) {
        while (actor) {
            if (actor.name === DOCK_NAME)
                return true;
            actor = actor.get_parent();
        }
        return false;
    }

    _cancelCheck() {
        if (this._checkId) {
            GLib.source_remove(this._checkId);
            this._checkId = 0;
        }
    }

    _onKeyFocus() {
        if (this._isInDock(global.stage.get_key_focus())) {
            this._inDock = true;
            this._cancelCheck();
            return;
        }
        if (!this._inDock || this._checkId)
            return;
        this._checkId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, LEAVE_DELAY_MS, () => {
            this._checkId = 0;
            if (!this._isInDock(global.stage.get_key_focus())) {
                this._inDock = false;
                this._nudge();
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    _nudge() {
        if (this._timeoutId)
            return;
        this._savedValue = this._settings.get_boolean('intellihide');
        this._settings.set_boolean('intellihide', !this._savedValue);
        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
            this._settings.set_boolean('intellihide', this._savedValue);
            this._timeoutId = 0;
            return GLib.SOURCE_REMOVE;
        });
    }
}
