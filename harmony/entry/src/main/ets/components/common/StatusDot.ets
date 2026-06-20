import { ConnectionState } from '../../models/ShellModels';
import { EggClipColors } from '../../theme/Colors';

@Component
export struct StatusDot {
  state: ConnectionState = ConnectionState.OFFLINE;

  private dotColor(): ResourceColor {
    if (this.state === ConnectionState.ONLINE) {
      return EggClipColors.statusOnline;
    }

    if (this.state === ConnectionState.CONNECTING) {
      return EggClipColors.primary;
    }

    return EggClipColors.textSecondary;
  }

  build() {
    Circle({ width: 9, height: 9 })
      .fill(this.dotColor())
  }
}
