import { common } from '@kit.AbilityKit';
import {
  EGGCLIP_MDNS_SERVICE_TYPE,
  MdnsServiceCandidate,
  PocLifecycleState
} from '../models/PocModels';
import { StatusDot } from '../components/common/StatusDot';
import { ConnectionState } from '../models/ShellModels';
import {
  PocConnectionSnapshot,
  pocConnectionStore
} from '../store/PocConnectionStore';
import { TrustedDeviceStore, TrustedDeviceSummary } from '../store/TrustedDeviceStore';
import {
  PairingConnectionSnapshot,
  PairingConnectionState,
  pairingConnectionStore
} from '../store/PairingConnectionStore';
import { EggClipColors } from '../theme/Colors';
import { EggClipSpacing } from '../theme/Spacing';
import { EggClipTypography } from '../theme/Typography';
import { APP_FOREGROUND_STORAGE_KEY } from '../utils/AppLifecycle';
import { PairingPage } from './PairingPage';
import { UiMessageDescriptor } from '../services/localization/UiMessageCodes';
import { UiMessageFormatter } from '../services/localization/UiMessageFormatter';
import { LocalizedFormatter } from '../services/localization/LocalizedFormatter';
import { DisplayNameOrigin } from '../data/repositories/RepositoryCommands';

@Component
export struct DevicesPage {
  private trustedDeviceStore: TrustedDeviceStore | null = null;
  private messageFormatter: UiMessageFormatter | null = null;
  private readonly localizedFormatter: LocalizedFormatter = new LocalizedFormatter();
  private readonly connectionSnapshotListener = (snapshot: PocConnectionSnapshot): void => {
    this.manualHost = snapshot.manualHost;
    this.manualPort = snapshot.manualPort;
    this.lastSuccessfulHost = snapshot.lastSuccessfulHost;
    this.lastSuccessfulPort = snapshot.lastSuccessfulPort;
    this.lastSuccessfulEndpointLabel = snapshot.lastSuccessfulEndpointLabel;
    this.lastSuccessfulAtMs = snapshot.lastSuccessfulAtMs;
    this.discoveryState = snapshot.discoveryState;
    this.discoveryStatus = this.formatMessage(snapshot.discoveryStatus);
    this.discoveryCandidates = snapshot.discoveryCandidates;
    this.transportState = snapshot.transportState;
    this.transportStatus = this.formatMessage(snapshot.transportStatus);
    this.transportDiagnostics = this.formatMessage(snapshot.transportDiagnostics);
    this.connectionState = snapshot.connectionState;
    this.connectionTitle = this.formatMessage(snapshot.connectionTitle);
    this.connectionDescription = this.formatMessage(snapshot.connectionDescription);
  };
  private readonly pairingSnapshotListener = (snapshot: PairingConnectionSnapshot): void => {
    this.pairingConnectionState = snapshot.state;
    this.pairingAuthenticated = snapshot.authenticated;
    this.pairingTrustedDeviceId = snapshot.trustedDeviceId;
    this.loadTrustedDevices();
  };
  @StorageLink(APP_FOREGROUND_STORAGE_KEY) @Watch('onAppForegroundChanged')
  private appInForeground: boolean = false;
  @State private manualHost: string = '127.0.0.1';
  @State private manualPort: string = '0';
  @State private lastSuccessfulHost: string = '';
  @State private lastSuccessfulPort: string = '';
  @State private lastSuccessfulEndpointLabel: string = '';
  @State private lastSuccessfulAtMs: number = 0;
  @State private discoveryState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private discoveryStatus: string = '';
  @State private discoveryCandidates: MdnsServiceCandidate[] = [];
  @State private transportState: PocLifecycleState = PocLifecycleState.IDLE;
  @State private transportStatus: string = '';
  @State private transportDiagnostics: string = '';
  @State private connectionState: ConnectionState = ConnectionState.OFFLINE;
  @State private connectionTitle: string = '';
  @State private connectionDescription: string = '';
  @State private pairingExpanded: boolean = false;
  @State private diagnosticsExpanded: boolean = false;
  @State private trustedDevices: TrustedDeviceSummary[] = [];
  @State private pairingConnectionState: PairingConnectionState = PairingConnectionState.IDLE;
  @State private pairingAuthenticated: boolean = false;
  @State private pairingTrustedDeviceId: string = '';
  @State private editingDeviceId: string = '';
  @State private deviceNameDraft: string = '';
  @State private busyDeviceId: string = '';
  @State private deviceActionStatus: string = '';
  @State private gettingStartedDetail: string = '';

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      const context = hostContext as common.UIAbilityContext;
      this.messageFormatter = new UiMessageFormatter(context);
      pocConnectionStore.initialize(context);
      if (this.trustedDeviceStore === null) {
        this.trustedDeviceStore = new TrustedDeviceStore(context);
      }
    }
    pocConnectionStore.subscribe(this.connectionSnapshotListener);
    pairingConnectionStore.subscribe(this.pairingSnapshotListener);
    this.loadTrustedDevices();
  }

  aboutToDisappear(): void {
    pocConnectionStore.unsubscribe(this.connectionSnapshotListener);
    pairingConnectionStore.unsubscribe(this.pairingSnapshotListener);
  }

  build() {
    Scroll() {
      Column({ space: EggClipSpacing.sectionGap }) {
        this.Header()
        if (this.trustedDevices.length === 0) {
          this.GettingStartedSection()
        }
        GridRow({
          columns: { sm: 12, md: 12, lg: 12 },
          gutter: { x: EggClipSpacing.sectionGap, y: EggClipSpacing.sectionGap }
        }) {
          GridCol({ span: { sm: 12, md: 5, lg: 5 } }) {
            this.TrustedDevicesCard()
          }

          GridCol({ span: { sm: 12, md: 7, lg: 7 } }) {
            Column({ space: EggClipSpacing.sectionGap }) {
              this.AddDeviceSection()
              this.ConnectionDiagnosticsSection()
            }
            .width('100%')
          }
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxWidth: 960 })
      .alignSelf(ItemAlign.Center)
      .padding({
        left: EggClipSpacing.pagePadding,
        right: EggClipSpacing.pagePadding,
        top: EggClipSpacing.pagePadding,
        bottom: EggClipSpacing.floatingNavigationContentInset
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EggClipColors.pageBackground)
  }

  @Builder
  private GettingStartedSection() {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text(this.resourceText('devices_getting_started'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')

        Text(this.resourceText('devices_getting_started_intro'))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      GridRow({
        columns: 12,
        gutter: { x: 8, y: 8 }
      }) {
        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button(this.resourceText('devices_start_pairing'))
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.onPrimary)
            .backgroundColor(EggClipColors.primary)
            .borderRadius(18)
            .onClick(() => {
              this.pairingExpanded = true;
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button(this.resourceText('devices_feature_demo'))
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.gettingStartedDetail = this.gettingStartedDetail === 'features' ? '' : 'features';
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button(this.resourceText('devices_privacy'))
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.gettingStartedDetail = this.gettingStartedDetail === 'privacy' ? '' : 'privacy';
            })
        }

        GridCol({ span: { sm: 6, md: 3, lg: 3 } }) {
          Button(this.resourceText('devices_connection_diagnostics'))
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor(EggClipColors.textPrimary)
            .backgroundColor(EggClipColors.controlBackground)
            .borderRadius(18)
            .onClick(() => {
              this.diagnosticsExpanded = true;
              this.gettingStartedDetail = 'diagnostics';
            })
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        this.GettingStartedStep('1', this.resourceText('devices_step_launch_title'), this.resourceText('devices_step_launch_desc'))
        this.GettingStartedStep('2', this.resourceText('devices_step_network_title'), this.resourceText('devices_step_network_desc'))
        this.GettingStartedStep('3', this.resourceText('devices_step_invite_title'), this.resourceText('devices_step_invite_desc'))
        this.GettingStartedStep('4', this.resourceText('devices_step_pair_title'), this.resourceText('devices_step_pair_desc'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.gettingStartedDetail === 'features') {
        this.FeatureGuideCard()
      } else if (this.gettingStartedDetail === 'privacy') {
        this.PrivacyGuideCard()
      } else if (this.gettingStartedDetail === 'diagnostics') {
        Text(this.resourceText('devices_diagnostics_expanded'))
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }

      Text(this.resourceText('devices_invitation_security'))
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private GettingStartedStep(number: string, title: ResourceStr, description: ResourceStr) {
    Row({ space: 12 }) {
      Text(number)
        .width(26)
        .height(26)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.onPrimary)
        .textAlign(TextAlign.Center)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(13)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private FeatureGuideCard() {
    Column({ space: 8 }) {
      Text(this.resourceText('devices_core_features'))
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HelpPoint(this.resourceText('devices_feature_receive_title'), this.resourceText('devices_feature_receive_desc'))
      this.HelpPoint(this.resourceText('devices_feature_send_title'), this.resourceText('devices_feature_send_desc'))
      this.HelpPoint(this.resourceText('devices_feature_reconnect_title'), this.resourceText('devices_feature_reconnect_desc'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private PrivacyGuideCard() {
    Column({ space: 8 }) {
      Text(this.resourceText('devices_privacy_title'))
        .fontSize(EggClipTypography.captionSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.HelpPoint(this.resourceText('devices_privacy_lan_title'), this.resourceText('devices_privacy_lan_desc'))
      this.HelpPoint(this.resourceText('devices_privacy_local_title'), this.resourceText('devices_privacy_local_desc'))
      this.HelpPoint(this.resourceText('devices_privacy_system_title'), this.resourceText('devices_privacy_system_desc'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private HelpPoint(title: ResourceStr, description: ResourceStr) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(16)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)

        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private AddDeviceSection() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(this.resourceText('devices_add_device'))
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text(this.resourceText('devices_add_device_desc'))
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.pairingExpanded ? this.resourceText('common_collapse') : this.resourceText('devices_start_pairing'))
          .height(40)
          .fontSize(12)
          .fontColor(this.pairingExpanded ? EggClipColors.textSecondary : EggClipColors.onPrimary)
          .backgroundColor(this.pairingExpanded ? EggClipColors.controlBackground : EggClipColors.primary)
          .borderRadius(16)
          .onClick(() => {
            this.pairingExpanded = !this.pairingExpanded;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.pairingExpanded) {
        PairingPage()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private Header() {
    Column({ space: 6 }) {
      Text(this.resourceText('devices_title'))
        .fontSize(EggClipTypography.titleSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.resourceText('devices_auto_connect_desc'))
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ConnectionDiagnosticsSection() {
    Column({ space: 12 }) {
      Row() {
        Row({ space: 10 }) {
          StatusDot({ state: this.connectionState })

          Column({ space: 3 }) {
            Text(this.resourceText('devices_connection_issues'))
              .fontSize(EggClipTypography.bodySize)
              .fontWeight(FontWeight.Bold)
              .fontColor(EggClipColors.textPrimary)

            Text(this.diagnosticsSummary())
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(18)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        Button(this.diagnosticsExpanded ? this.resourceText('common_collapse') : this.resourceText('common_expand'))
          .height(40)
          .fontSize(12)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(16)
          .onClick(() => {
            this.diagnosticsExpanded = !this.diagnosticsExpanded;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(this.resourceText('devices_connection_issues_desc'))
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      if (this.diagnosticsExpanded) {
        this.ConnectionCard()
        if (this.hasRuntimeConnection()) {
          this.RuntimeDeviceCard()
        }
        this.DiscoveryCard()
        this.ManualTransportCard()
        this.TroubleshootingCard()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private ConnectionCard() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 12 }) {
          StatusDot({ state: this.connectionState })

          Column({ space: 4 }) {
            Text(this.connectionTitle)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(EggClipColors.textPrimary)

            Text(this.connectionDescription)
              .fontSize(EggClipTypography.captionSize)
              .fontColor(EggClipColors.textSecondary)
              .lineHeight(20)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        Text(this.connectionStateLabel())
          .fontSize(11)
          .fontColor(this.connectionStateColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')

    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusLarge)
  }

  @Builder
  private RuntimeDeviceCard() {
    Column({ space: 12 }) {
      Row() {
        Text(this.resourceText('devices_runtime'))
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.runtimeDeviceKind())
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
      }
      .width('100%')

      Row({ space: 10 }) {
        StatusDot({ state: this.connectionState })

        Column({ space: 4 }) {
          Text(this.runtimeDeviceName())
            .fontSize(EggClipTypography.bodySize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(this.runtimeDeviceDescription())
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.DeviceInfoRow(this.resourceText('devices_short_fingerprint'),
        this.transportState === PocLifecycleState.RUNNING ?
          this.resourceText('devices_unpaired') : this.resourceText('devices_waiting_pairing'))
      this.DeviceInfoRow(this.resourceText('devices_last_online'), this.runtimeLastSeenText())
      this.DeviceInfoRow(this.resourceText('devices_endpoint'), this.runtimeEndpointText())

      Text(this.resourceText('devices_runtime_notice'))
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private DeviceInfoRow(label: ResourceStr, value: ResourceStr) {
    Row({ space: 10 }) {
      Text(label)
        .width(72)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)

      Text(value)
        .layoutWeight(1)
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textPrimary)
        .lineHeight(18)
    }
    .width('100%')
  }

  @Builder
  private DiscoveryCard() {
    Column({ space: 10 }) {
      Row() {
        Text(this.resourceText('devices_discovery'))
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.lifecycleStateLabel(this.discoveryState))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(this.discoveryState === PocLifecycleState.FAILED ?
            EggClipColors.statusError : EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.discoveryStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Button(this.discoveryActionLabel())
        .width('100%')
        .height(40)
        .fontColor(this.isDiscoveryActive() ? EggClipColors.textSecondary : EggClipColors.onPrimary)
        .backgroundColor(this.isDiscoveryActive() ? EggClipColors.controlBackground : EggClipColors.primary)
        .borderRadius(19)
        .onClick(() => {
          this.toggleDiscovery();
        })

      if (this.discoveryCandidates.length === 0) {
        Text(this.resourceText('devices_discovery_empty'))
          .width('100%')
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(20)
      } else {
        ForEach(this.discoveryCandidates, (candidate: MdnsServiceCandidate) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(`${candidate.host}:${candidate.port}`)
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textPrimary)
              Text(this.resourceText('devices_protocol_version', candidate.protocolVersion === 0 ?
                this.resourceText('devices_protocol_experimental') : candidate.protocolVersion))
                .fontSize(EggClipTypography.captionSize)
                .fontColor(EggClipColors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(this.resourceText('common_connect'))
              .height(40)
              .fontColor(EggClipColors.accentForeground)
              .backgroundColor(EggClipColors.cardBackground)
              .borderRadius(17)
              .onClick(() => {
                pocConnectionStore.connectCandidate(candidate);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
        }, (candidate: MdnsServiceCandidate) => candidate.instanceId)
      }

      Text(this.resourceText('devices_service_state', EGGCLIP_MDNS_SERVICE_TYPE,
        this.lifecycleStateLabel(this.transportState)))
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private ManualTransportCard() {
    Column({ space: 12 }) {
      Row() {
        Text(this.resourceText('devices_manual'))
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .layoutWeight(1)

        Text(this.lifecycleStateLabel(this.transportState))
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
      }
      .width('100%')

      Text(this.resourceText('devices_manual_desc'))
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Row({ space: 8 }) {
        TextInput({ text: this.manualHost, placeholder: this.resourceText('pairing_desktop_ip') })
          .layoutWeight(1)
          .height(42)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
          .onChange((value: string) => {
            this.manualHost = value;
          })

        TextInput({ text: this.manualPort, placeholder: this.resourceText('pairing_port') })
          .width(96)
          .height(42)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(14)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.manualPort = value;
          })
      }
      .width('100%')

      if (this.lastSuccessfulEndpointLabel.length > 0) {
        this.RecentEndpointCard()
      }

      Button(this.resourceText('devices_connect_desktop'))
        .width('100%')
        .height(44)
        .fontColor(EggClipColors.onPrimary)
        .backgroundColor(EggClipColors.primary)
        .borderRadius(22)
        .onClick(() => {
          pocConnectionStore.connectManualEndpoint(this.manualHost, this.manualPort);
        })

      Button(this.resourceText('devices_disconnect_desktop'))
        .width('100%')
        .height(40)
        .fontColor(EggClipColors.textSecondary)
        .backgroundColor(EggClipColors.controlBackground)
        .borderRadius(20)
        .onClick(() => {
          pocConnectionStore.disconnectManualEndpoint();
        })

      Text(this.transportStatus)
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      Text(this.transportDiagnostics)
        .width('100%')
        .fontSize(11)
        .fontColor(EggClipColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private RecentEndpointCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.resourceText('devices_recent_endpoint'))
            .fontSize(EggClipTypography.captionSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(EggClipColors.textPrimary)

          Text(this.resourceText('devices_recent_endpoint_meta', this.lastSuccessfulEndpointLabel,
            this.localizedFormatter.formatTime(this.lastSuccessfulAtMs)))
            .fontSize(11)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.resourceText('devices_fill_endpoint'))
          .height(40)
          .fontSize(11)
          .fontColor(EggClipColors.textSecondary)
          .backgroundColor(EggClipColors.cardBackground)
          .borderRadius(15)
          .onClick(() => {
            this.manualHost = this.lastSuccessfulHost;
            this.manualPort = this.lastSuccessfulPort;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Button(this.resourceText('devices_connect_recent'))
        .width('100%')
        .height(40)
        .fontColor(EggClipColors.accentForeground)
        .backgroundColor(EggClipColors.cardBackground)
        .borderRadius(19)
        .onClick(() => {
          pocConnectionStore.connectLastSuccessfulEndpoint();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(EggClipColors.controlBackground)
    .borderRadius(14)
  }

  @Builder
  private TroubleshootingCard() {
    Column({ space: 12 }) {
      Text(this.resourceText('devices_troubleshooting'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      Text(this.troubleshootingHint())
        .width('100%')
        .fontSize(EggClipTypography.captionSize)
        .fontColor(EggClipColors.textSecondary)
        .lineHeight(20)

      this.TroubleshootingRow(this.resourceText('devices_troubleshoot_discovery_title'), this.discoveryCandidates.length > 0
        ? this.pluralText('devices_candidates_connect_plural', this.discoveryCandidates.length)
        : this.resourceText('devices_troubleshoot_discovery_empty'))
      this.TroubleshootingRow(this.resourceText('devices_troubleshoot_manual_title'),
        this.resourceText('devices_troubleshoot_manual_desc'))
      this.TroubleshootingRow(this.resourceText('devices_troubleshoot_vpn_title'),
        this.resourceText('devices_troubleshoot_vpn_desc'))
      this.TroubleshootingRow(this.resourceText('devices_troubleshoot_security_title'),
        this.resourceText('devices_troubleshoot_security_desc'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private TroubleshootingRow(title: ResourceStr, description: ResourceStr) {
    Row({ space: 10 }) {
      Text('·')
        .fontSize(20)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.captionSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private TrustedDevicesCard() {
    if (this.trustedDevices.length > 0) {
      Column({ space: 12 }) {
        Text(this.resourceText('devices_trusted'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(EggClipColors.textPrimary)
          .width('100%')
        ForEach(this.trustedDevices, (device: TrustedDeviceSummary) => {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text(this.trustedDeviceDisplayName(device))
                  .fontSize(EggClipTypography.bodySize)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(EggClipColors.textPrimary)
                Text(this.resourceText('devices_fingerprint_last_seen', device.shortFingerprint,
                  device.lastSeenAt === undefined ? this.resourceText('devices_never_online') :
                    this.localizedFormatter.formatDateTime(device.lastSeenAt)))
                  .fontSize(EggClipTypography.captionSize)
                  .fontColor(EggClipColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.trustedDeviceStateLabel(device.deviceId))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.trustedDeviceStateColor(device.deviceId))
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .backgroundColor(EggClipColors.cardBackground)
                .borderRadius(14)
            }
            .width('100%')

            if (this.editingDeviceId === device.deviceId) {
              Row({ space: 8 }) {
                TextInput({ text: this.deviceNameDraft, placeholder: this.resourceText('devices_name_placeholder') })
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(EggClipTypography.captionSize)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(18)
                  .onChange((value: string) => {
                    this.deviceNameDraft = value;
                  })

                Button(this.resourceText('common_save'))
                  .height(40)
                  .fontSize(12)
                  .fontColor(this.busyDeviceId.length === 0 ?
                    EggClipColors.onPrimary : EggClipColors.textSecondary)
                  .backgroundColor(this.busyDeviceId.length === 0 ?
                    EggClipColors.primary : EggClipColors.controlBackground)
                  .borderRadius(17)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.saveDeviceName(device.deviceId);
                  })

                Button(this.resourceText('common_cancel'))
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.textSecondary)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(17)
                  .onClick(() => {
                    this.editingDeviceId = '';
                    this.deviceNameDraft = '';
                  })
              }
              .width('100%')
            } else {
              Row({ space: 8 }) {
                Button(this.resourceText('common_rename'))
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.textPrimary)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(16)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.editingDeviceId = device.deviceId;
                    this.deviceNameDraft = this.trustedDeviceDisplayName(device);
                    this.deviceActionStatus = '';
                  })

                Button(this.busyDeviceId === device.deviceId ?
                  this.resourceText('devices_removing') : this.resourceText('devices_remove'))
                  .height(40)
                  .fontSize(12)
                  .fontColor(EggClipColors.statusError)
                  .backgroundColor(EggClipColors.cardBackground)
                  .borderRadius(16)
                  .enabled(this.busyDeviceId.length === 0)
                  .onClick(() => {
                    this.confirmRemoveDevice(device);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor(EggClipColors.controlBackground)
          .borderRadius(EggClipSpacing.radiusMedium)
        }, (device: TrustedDeviceSummary) => device.deviceId)

        if (this.deviceActionStatus.length > 0) {
          Text(this.deviceActionStatus)
            .width('100%')
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .lineHeight(18)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(EggClipSpacing.cardPadding)
      .backgroundColor(EggClipColors.cardBackground)
      .borderRadius(EggClipSpacing.radiusLarge)
    } else {
      Column({ space: 14 }) {
        Text('◌')
          .fontSize(42)
          .fontColor(EggClipColors.accentForeground)

        Column({ space: 6 }) {
          Text(this.resourceText('devices_trusted'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(EggClipColors.textPrimary)

          Text(this.resourceText('devices_empty_trusted'))
            .fontSize(EggClipTypography.captionSize)
            .fontColor(EggClipColors.textSecondary)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding(EggClipSpacing.cardPadding)
      .backgroundColor(EggClipColors.cardBackground)
      .borderRadius(EggClipSpacing.radiusLarge)
    }
  }

  private loadTrustedDevices(): void {
    if (this.trustedDeviceStore === null) return;
    this.trustedDeviceStore.load()
      .then((devices) => { this.trustedDevices = devices; })
      .catch(() => { this.trustedDevices = []; });
  }

  private saveDeviceName(deviceId: string): void {
    if (this.trustedDeviceStore === null || this.busyDeviceId.length > 0) return;
    this.busyDeviceId = deviceId;
    this.trustedDeviceStore.rename(deviceId, this.deviceNameDraft)
      .then((result) => {
        this.busyDeviceId = '';
        if (!result.ok) {
          this.deviceActionStatus = result.reason === undefined ? this.resourceText('devices_rename_failed') :
            this.formatMessage(result.reason);
          return;
        }
        this.editingDeviceId = '';
        this.deviceNameDraft = '';
        this.deviceActionStatus = this.resourceText('devices_renamed');
        this.loadTrustedDevices();
      })
      .catch(() => {
        this.busyDeviceId = '';
        this.deviceActionStatus = this.resourceText('devices_rename_retry');
      });
  }

  private confirmRemoveDevice(device: TrustedDeviceSummary): void {
    this.getUIContext().showAlertDialog({
      title: this.resourceText('devices_remove_dialog_title', this.trustedDeviceDisplayName(device)),
      message: this.resourceText('devices_remove_message'),
      primaryButton: {
        value: this.resourceText('common_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: this.resourceText('devices_remove_confirm'),
        fontColor: EggClipColors.statusError,
        action: () => {
          this.removeDevice(device.deviceId);
        }
      }
    });
  }

  private removeDevice(deviceId: string): void {
    if (this.trustedDeviceStore === null || this.busyDeviceId.length > 0) return;
    this.busyDeviceId = deviceId;
    this.editingDeviceId = '';
    pairingConnectionStore.close();
    this.trustedDeviceStore.removeAndClearPairingSecurity(deviceId)
      .then((result) => {
        this.busyDeviceId = '';
        if (!result.ok) {
          this.deviceActionStatus = result.reason === undefined ?
            this.resourceText('devices_remove_incomplete') : this.formatMessage(result.reason);
          this.loadTrustedDevices();
          return;
        }
        this.deviceActionStatus = this.resourceText('devices_removed');
        this.loadTrustedDevices();
      })
      .catch(() => {
        this.busyDeviceId = '';
        this.deviceActionStatus = this.resourceText('devices_remove_failed');
        this.loadTrustedDevices();
      });
  }

  private trustedDeviceDisplayName(device: TrustedDeviceSummary): string {
    return device.nameOrigin === DisplayNameOrigin.GENERATED ?
      this.resourceText('devices_generated_name', device.shortFingerprint) : device.displayName;
  }

  private trustedDeviceStateLabel(deviceId: string): string {
    if (deviceId !== this.pairingTrustedDeviceId) return this.resourceText('common_offline');
    if (this.pairingAuthenticated || this.pairingConnectionState === PairingConnectionState.AUTHENTICATED) {
      return this.resourceText('common_online');
    }
    if (this.pairingConnectionState === PairingConnectionState.PREPARING ||
      this.pairingConnectionState === PairingConnectionState.CONNECTING ||
      this.pairingConnectionState === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.pairingConnectionState === PairingConnectionState.WAITING_AUTH_OK) return this.resourceText('common_connecting');
    if (this.pairingConnectionState === PairingConnectionState.FAILED) {
      return this.resourceText('common_connection_failed');
    }
    return this.resourceText('common_offline');
  }

  private trustedDeviceStateColor(deviceId: string): ResourceColor {
    if (deviceId !== this.pairingTrustedDeviceId) return EggClipColors.textSecondary;
    if (this.pairingAuthenticated || this.pairingConnectionState === PairingConnectionState.AUTHENTICATED) {
      return EggClipColors.statusOnline;
    }
    if (this.pairingConnectionState === PairingConnectionState.PREPARING ||
      this.pairingConnectionState === PairingConnectionState.CONNECTING ||
      this.pairingConnectionState === PairingConnectionState.CLIENT_HELLO_SENT ||
      this.pairingConnectionState === PairingConnectionState.WAITING_AUTH_OK) return EggClipColors.statusPending;
    if (this.pairingConnectionState === PairingConnectionState.FAILED) return EggClipColors.statusError;
    return EggClipColors.textSecondary;
  }

  @Builder
  private DevicePolicyCard() {
    Column({ space: 12 }) {
      Text(this.resourceText('devices_rules'))
        .fontSize(EggClipTypography.bodySize)
        .fontWeight(FontWeight.Bold)
        .fontColor(EggClipColors.textPrimary)
        .width('100%')

      this.PolicyRow(this.resourceText('devices_rule_limit_title'), this.resourceText('devices_rule_limit_desc'))
      this.PolicyRow(this.resourceText('devices_rule_pair_title'), this.resourceText('devices_rule_pair_desc'))
      this.PolicyRow(this.resourceText('devices_rule_rotate_title'), this.resourceText('devices_rule_rotate_desc'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(EggClipSpacing.cardPadding)
    .backgroundColor(EggClipColors.cardBackground)
    .borderRadius(EggClipSpacing.radiusMedium)
  }

  @Builder
  private PolicyRow(title: ResourceStr, description: ResourceStr) {
    Row({ space: 10 }) {
      Text('•')
        .fontSize(20)
        .fontColor(EggClipColors.accentForeground)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(EggClipTypography.bodySize)
          .fontWeight(FontWeight.Medium)
          .fontColor(EggClipColors.textPrimary)
        Text(description)
          .fontSize(EggClipTypography.captionSize)
          .fontColor(EggClipColors.textSecondary)
          .lineHeight(19)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  private onAppForegroundChanged(): void {
    pocConnectionStore.handleForegroundChanged(this.appInForeground);
  }

  private connectionStateLabel(): string {
    if (this.connectionState === ConnectionState.ONLINE) {
      return this.resourceText('common_online');
    }
    if (this.connectionState === ConnectionState.CONNECTING) {
      return this.resourceText('common_connecting');
    }
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return this.resourceText('common_authentication_failed');
    }
    if (this.connectionState === ConnectionState.PAUSED) {
      return this.resourceText('common_paused');
    }
    return this.resourceText('common_offline');
  }

  private connectionStateColor(): ResourceColor {
    if (this.connectionState === ConnectionState.ONLINE) {
      return EggClipColors.statusOnline;
    }
    if (this.connectionState === ConnectionState.CONNECTING) {
      return EggClipColors.statusPending;
    }
    if (this.connectionState === ConnectionState.AUTH_FAILED) {
      return EggClipColors.statusError;
    }
    return EggClipColors.textSecondary;
  }

  private runtimeDeviceKind(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_runtime_diagnostic');
    }
    return this.resourceText('devices_runtime_record');
  }

  private runtimeDeviceName(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_runtime_temporary');
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_runtime_failed');
    }
    return this.resourceText('devices_runtime_waiting');
  }

  private runtimeDeviceDescription(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_runtime_online_desc');
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_runtime_failed_desc');
    }
    return this.resourceText('devices_runtime_waiting_desc');
  }

  private runtimeLastSeenText(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_current_online');
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return this.resourceText('common_connection_failed');
    }
    return this.resourceText('common_none');
  }

  private runtimeEndpointText(): string {
    const port = this.manualPort.length > 0 ? this.manualPort : this.resourceText('common_not_set');
    return `${this.manualHost}:${port}`;
  }

  private hasRuntimeConnection(): boolean {
    return this.transportState !== PocLifecycleState.IDLE &&
      this.manualHost.trim().length > 0 &&
      this.manualPort.length > 0 &&
      this.manualPort !== '0';
  }

  private lifecycleStateLabel(state: PocLifecycleState): string {
    if (state === PocLifecycleState.STARTING) {
      return this.resourceText('common_starting');
    }
    if (state === PocLifecycleState.RUNNING) {
      return this.resourceText('common_running');
    }
    if (state === PocLifecycleState.FAILED) {
      return this.resourceText('common_failed');
    }
    return this.resourceText('common_not_started');
  }

  private isDiscoveryActive(): boolean {
    return this.discoveryState === PocLifecycleState.STARTING ||
      this.discoveryState === PocLifecycleState.RUNNING;
  }

  private discoveryActionLabel(): string {
    if (this.isDiscoveryActive()) {
      return this.resourceText('devices_discovery_stop');
    }
    if (this.discoveryState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_discovery_retry');
    }
    return this.resourceText('devices_discovery_start');
  }

  private toggleDiscovery(): void {
    if (this.isDiscoveryActive()) {
      pocConnectionStore.stopDiscovery();
      return;
    }
    pocConnectionStore.startDiscovery();
  }

  private troubleshootingHint(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_hint_connected');
    }
    if (this.transportState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_hint_connection_failed');
    }
    if (this.discoveryState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_hint_discovery_failed');
    }
    if (!this.appInForeground) {
      return this.resourceText('devices_hint_background');
    }
    return this.resourceText('devices_hint_initial');
  }

  private diagnosticsSummary(): string {
    if (this.transportState === PocLifecycleState.RUNNING) {
      return this.resourceText('devices_summary_connected');
    }
    if (this.discoveryCandidates.length > 0) {
      return this.pluralText('devices_summary_candidates_plural', this.discoveryCandidates.length);
    }
    if (this.transportState === PocLifecycleState.FAILED || this.discoveryState === PocLifecycleState.FAILED) {
      return this.resourceText('devices_summary_failed');
    }
    return this.resourceText('devices_summary_check');
  }

  private formatMessage(message: UiMessageDescriptor): string {
    return this.messageFormatter === null ? message.code : this.messageFormatter.format(message);
  }

  private resourceText(name: string, ...args: Array<string | number>): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) return name;
    try {
      return hostContext.resourceManager.getStringByNameSync(name, ...args);
    } catch (_) {
      return name;
    }
  }

  private pluralText(name: string, count: number): string {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) return name;
    try {
      return hostContext.resourceManager.getIntPluralStringByNameSync(name, count, count);
    } catch (_) {
      return name;
    }
  }
}
