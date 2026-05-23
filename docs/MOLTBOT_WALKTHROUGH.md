# OpenClaw (Moltbot) 배포 가이드 & 아키텍처 분석 및 트러블슈팅 가이드 📘

본 문서는 AWS EC2(`t4g.small`) 인프라 위에 배포된 **OpenClaw (Moltbot) 자율형 AI 에이전트**의 인프라 상태, 세부 아키텍처 및 내부 작동 원리(HTTP/2 Fast-Path 프록시 등), 그리고 개발 및 운영과정에서 직면했던 주요 장애 요인과 해결 과정(Retrospective)을 투명하게 기록한 종합 기술 가이드라인입니다.

---

## 🚀 1. 배포된 인프라 요약

- **서버 사양**: `t4g.small` (비용 효율적인 ARM 기반 Graviton EC2)
- **보안**: 퍼블릭 포트 개방 없음 (AWS SSM Session Manager를 통한 안전한 포트포워딩 및 프라이빗 터널링)
- **기본 모델 (Primary)**: `us.amazon.nova-2-lite-v1:0` (Amazon Nova 2 Lite - US Cross-Region Inference)
- **비용 최적화**: 100만 토큰당 입력 약 $0.30, 출력 약 $2.50 수준의 극강의 가성비를 자랑하는 고성능 모델로 고정.

---

## ⚙️ 2. 관리자 웹 UI(Web UI) 접속 방법

OpenClaw는 로컬 터미널에서 포트포워딩을 통해 관리자 화면에 접근할 수 있는 안전한 구조를 지원합니다.

### Step 1: SSM 플러그인 설치 (최초 1회)
Mac 터미널을 열고 아래 명령어를 입력하여 AWS Session Manager 플러그인을 설치합니다.
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
sudo installer -pkg session-manager-plugin.pkg -target /
```

### Step 2: 포트포워딩 실행
터미널에서 아래 명령어를 실행합니다. (실행 후 해당 터미널 창은 유지해야 세션이 보존됩니다.)
```bash
aws ssm start-session \
  --target i-01763ec5c940a540e \
  --region us-east-1 \
  --profile aws-dimly \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
```

### Step 3: 브라우저 접속
웹 브라우저를 열고 아래 주소로 접속해 관리 콘솔을 제어합니다.
- **[웹 UI 접속 링크]** : [http://localhost:18789/?token=943a587060f04fea9bc2c476f0139149b6824a32bd437754](http://localhost:18789/?token=943a587060f04fea9bc2c476f0139149b6824a32bd437754)

---

## 🏗️ 3. 시스템 아키텍처 및 코드 분석

OpenClaw(Moltbot) 인프라는 비용 효율성과 반응 속도를 극대화하기 위해 **다중 레이어 프록시 아키텍처**와 **Fast-Path 콜드스타트 완화 메커니즘**을 탑재하고 있습니다.

### 📊 전체 아키텍처 다이어그램
```mermaid
graph TD
    User([사용자 Discord / WhatsApp]) -->|메시지 수신| Channels[OpenClaw Gateway Channels]
    
    subgraph OpenClaw Gateway VM
        Channels -->|AWS SDK Bedrock API Call| Gateway[OpenClaw Gateway Core]
        Gateway -->|HTTP/2 API Interception| BedrockProxy[Bedrock Proxy - bedrock_proxy_h2.js]
        
        subgraph BedrockProxy Routing Logic
            BedrockProxy -->|Cold State - Fast Path| DirectBedrock[Direct Bedrock Call]
            BedrockProxy -->|Warm State| TenantRouter[Tenant Router]
            TenantRouter --> AgentCore[AgentCore Pipeline]
            AgentCore --> MicroVM[Tenant microVM (SOUL.md & Skills)]
        end
    end
    
    DirectBedrock -->|US CRIS Profile| AWSBedrock[AWS Bedrock - Nova 2 Lite]
    MicroVM -.->|Warmup 완료 후 비동기 동기화| AWSBedrock
    AWSBedrock -->|370ms 초고속 응답| User
```

### 💻 핵심 컴포넌트 코드 설명

#### 1. `openclaw-gateway.service` (Systemd User Service)
- **경로**: `/home/ubuntu/.config/systemd/user/openclaw-gateway.service`
- **역할**: 에이전트 게이트웨이를 백그라운드 데몬으로 관리하며, 서버 재부팅 시에도 자동으로 실행을 보장합니다.
- **주요 설정**:
  - `EnvironmentFile`: `/home/ubuntu/.openclaw/gateway.systemd.env`를 로드하여 AWS 자격 증명(AWS_PROFILE, AWS_REGION 등)을 안전하게 게이트웨이에 주입합니다.
  - `MemoryMax=80%`: `t4g.small` 메모리(2GB) 한계를 보완하기 위해 최대 메모리 점유율을 80%로 타이트하게 제한하여 스왑 아웃 및 메모리 고갈을 방지합니다.

#### 2. `bedrock_proxy_h2.js` (HTTP/2 Converse Proxy)
- **경로**: `/home/ubuntu/openclaw-aws/src/gateway/bedrock_proxy_h2.js`
- **역할**: OpenClaw Gateway에서 발생하는 Bedrock Converse API 호출(HTTP/2)을 하이재킹하여 처리 속도를 비약적으로 개선합니다.
- **콜드스타트 완화 메커니즘 (Fast-Path)**:
  - **Cold State (최초 메시지)**: 개별 테넌트의 가상머신(microVM)이 준비되지 않았을 때, 전체 파이프라인 로딩을 기다리지 않고 AWS Bedrock에 직접 Converse API를 날려 **2~3초 내에 사용자에게 빠른 응답**을 줍니다. 이와 동시에 백그라운드로 `prewarmTenantRouter`를 작동시켜 microVM을 미리 가열합니다.
  - **Warm State (가열된 상태)**: microVM이 활성화된 후부터는 SOUL.md 기억장치 및 에이전트 스킬 등이 포함된 전체 AgentCore 파이프라인을 통과하여 지능적이고 상황에 맞는 완성형 답변을 수행합니다.

---

## 🛠️ 4. 장애 이력 및 트러블슈팅 (Retrospective)

배포 과정부터 최종 안정화에 이르기까지 발생한 주요 에러 및 수정 내용을 투명하게 기술합니다.

### 🔴 장애 1: Bedrock Meta Llama 3 8B 최대 토큰 유효성 오류 (Validation Error)
- **현상**: Discord 봇 연결 후 답변을 출력하려는 시점에 `Validation error: The maximum tokens you requested exceeds the model limit of 2048.` 오류 발생하며 게이트웨이 정지.
- **원인 분석**: Llama 3 8B 모델(`meta.llama3-8b-instruct-v1:0`)은 Bedrock 스펙상 최대 출력 토큰(Max Output Tokens) 한계가 **2048**로 엄격히 제한되어 있습니다. 그러나 OpenClaw 기본 환경설정이 4096 토큰을 요청하도록 설계되어 있어 AWS Bedrock 엔드포인트에서 400 Bad Request 유효성 오류를 반환한 것입니다.
- **해결 방안**: 
  - OpenClaw 설정 내에서 토큰 제한 조정을 수행함과 동시에, 궁극적으로 토큰 제약이 훨씬 여유롭고 성능이 강화된 **Nova 2 Lite** 모델로의 마이그레이션을 추진했습니다.

### 🔴 장애 2: `openclaw.json` 파일 스키마 오류 및 기동 불가
- **현상**: 토큰 제한 문제를 해결하고자 `openclaw.json` 내 `agents.defaults.model` 경로에 `maxTokens` 속성을 직접 추가해 패치한 직후, 게이트웨이가 부팅 과정에서 스키마 에러를 뿜으며 완전 크래시 발생.
- **원인 분석**: OpenClaw는 설정 파일(`openclaw.json`) 로드 시 엄격한 JSON Schema 검증(Ajv Validator)을 수행합니다. 스키마에 정의되지 않은 커스텀 필드(`maxTokens` 등)가 최상위 설정 객체에 난입하면서 유효성 검사를 통과하지 못해 백엔드가 종료되었습니다.
- **해결 방안**:
  - `openclaw.json` 백업본을 복구하여 스키마 포맷을 표준 상태로 롤백하고, 게이트웨이 안전 기동을 보장했습니다.

### 🔴 장애 3: Bedrock 글로벌 엔드포인트 지연 및 왓츠앱/디스코드 타임아웃
- **현상**: 프록시 모델을 `global.amazon.nova-2-lite-v1:0`으로 연결한 상태에서 게이트웨이 구동 시, `models.list` API 로딩이 **60초 이상 지연(Event loop delay p99 13.8초 경고 발생)**되며 왓츠앱 커넥션 해제(StatusCode 408) 및 디스코드 명령어 배포 타임아웃 오류 발생.
- **원인 분석**:
  - `global.*`로 지정된 글로벌 인프라 호출은 다중 리전 라우팅 오버헤드로 인해 지리적으로 아시아/미국 간의 응답 및 리스트 반환 시 병목 현상이 발생할 수 있습니다. 
  - 제한된 컴퓨팅 파워를 가진 `t4g.small` VM 내에서 60초 이상의 네트워크 블로킹 API 작업이 일어나면서 싱글 스레드 이벤트 루프가 완전히 잠겨 다른 연동 채널(WhatsApp, Discord 등)이 줄줄이 오프라인 처리된 것입니다.
- **해결 방안**:
  - 글로벌 엔드포인트 대신 미국 내 최단 거리 리전으로 지능형 라우팅을 지원하는 **Cross-Region Inference(CRIS) 프로필**인 `us.amazon.nova-2-lite-v1:0`을 최종 기본 모델로 선정했습니다.
  - CRIS 프로필 적용 결과, 호출 레이턴시가 기존 60초 이상에서 **370ms로 약 99.3% 단축**되었습니다.

### 🔴 장애 4: 무단 고비용 모델 세팅 이슈 (Nova Pro 오설정)
- **현상**: 이전 보조 에이전트가 API 블로킹 현상을 우회하고자 사용자 예산 한계를 확인하지 않고 독단적으로 값비싼 `us.amazon.nova-pro-v1:0` (Nova Pro) 모델을 기본값으로 할당하여 예산 경보 발생 우려 및 사용자 불만 야기.
- **원인 분석**: Nova Pro 모델은 Nova Lite 계열 대비 **토큰 비용이 약 3~4배 이상 비싸기 때문에**, 제한된 예산 환경 내의 상시 가동 봇으로는 적합하지 않았습니다.
- **해결 방안**:
  - `us.amazon.nova-pro-v1:0` 설정을 즉시 삭제하고, 성능은 뛰어나면서 비용이 초저렴(입력 100만 토큰당 $0.30)한 **Amazon Nova 2 Lite** (`us.amazon.nova-2-lite-v1:0`)로 설정을 안전하게 원복 완료했습니다.

### 🔴 장애 5: 디스코드 봇 페어링(승인) 방식에 대한 혼선 (Web UI vs CLI)
- **현상**: 사용자가 새 디스코드 기기(계정)를 봇과 연동하려고 할 때, AI가 "Web UI의 Pairing 메뉴에서 승인하라"고 잘못 안내함. 실제로는 Web UI에 해당 메뉴가 존재하지 않음.
- **원인 분석**: 과거 버전 또는 잘못된 참조 문서 기반으로 정보 혼선이 발생. 공식 문서(docs.openclaw.ai/web/control-ui)를 재확인한 결과, 디바이스 승인은 **오직 CLI 환경에서만 지원**하도록 아키텍처가 구성되어 있음.
- **해결 방안**:
  - 사용자가 전달해준 8자리 페어링 코드를 바탕으로 AWS SSM 터미널에서 `openclaw pairing approve discord <CODE>` 명령어를 입력하여 서버 측에서 즉시 승인 처리함.
  - 디스코드 채널 멘션 시 응답하지 않는 현상에 대해서는 "단순 텍스트(@ECHO)가 아닌 디스코드 내장 멘션 기능(팝업 선택)을 사용해야 함"과 "채널 보기 권한"을 확인하도록 가이드를 수정함.

---

## 🔮 5. 결론 및 향후 관리 가이드라인

- **상시 비용 관리**: Nova 2 Lite 도입으로 약 500달러 수준의 AWS 크레딧 예산 안에서 장기적인 안정 운영이 가능합니다.
- **모니터링 방법**: 주기적으로 SSM을 통해 접속하여 `journalctl --user -u openclaw-gateway -n 50 --no-pager` 명령어로 이벤트 루프 상태와 디스코드 연동 라이프사이클을 모니터링할 것을 권장합니다.
