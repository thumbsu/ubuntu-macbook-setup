# Debug: 03-macbook-drivers.sh 에러 수정

## 상황

`sudo ./setup.sh` 실행 중 `scripts/03-macbook-drivers.sh`에서 에러 발생.
WiFi가 안 되므로 폰 테더링으로 Claude Code를 설치한 상태.

## 이 프롬프트를 Claude Code에 복붙해서 실행

```
03-macbook-drivers.sh 스크립트가 에러로 실패했어. 디버깅해서 고쳐줘.

## 확인해야 할 것

1. 먼저 로그 확인:
   - `cat /var/log/ubuntu-setup.log` (setup.sh가 남긴 로그)
   - `sudo bash scripts/03-macbook-drivers.sh` 를 다시 실행해서 에러 메시지 직접 확인

2. 흔한 실패 원인:
   - `set -e` + `((var++))` 문제 (02에서 이미 수정한 패턴 - 03에도 있을 수 있음)
   - `broadcom-sta-dkms` DKMS 빌드 실패 (커널 헤더 버전 불일치)
   - `apt install` 실패 (패키지 없음, 의존성 충돌)
   - `modprobe wl` 실패 (블랙리스트 모듈 충돌)

3. 커널/하드웨어 정보 수집:
   - `uname -r` (현재 커널 버전)
   - `dpkg -l | grep linux-headers` (설치된 헤더)
   - `lspci | grep -i network` (네트워크 칩 확인)
   - `dkms status` (DKMS 모듈 상태)
   - `lsmod | grep -E "wl|b43|bcma|brcm"` (로드된 드라이버)

## 수정 규칙

- 스크립트 파일: ~/ubuntu-macbook-setup/scripts/03-macbook-drivers.sh
- `set -e` 환경이므로 `((var++)) || true` 패턴 필수
- 수정 후 `shellcheck scripts/03-macbook-drivers.sh` 통과 확인
- 수정 후 `sudo bash scripts/03-macbook-drivers.sh` 재실행으로 검증
- git commit + push (커밋 메시지 70자 이하, Co-Authored-By 없음)

## 하드웨어 정보

- MacBook Pro 2013 (Intel Core i5-4288U)
- Ubuntu 24.04 LTS
- Broadcom BCM4360 WiFi
- 드라이버: broadcom-sta-dkms (기본), bcmwl-kernel-source (폴백)
```

## 수동 디버깅이 필요한 경우

```bash
# 로그 확인
cat /var/log/ubuntu-setup.log

# 03 스크립트만 다시 실행
sudo bash ~/ubuntu-macbook-setup/scripts/03-macbook-drivers.sh

# DKMS 빌드 로그 확인 (broadcom-sta 실패 시)
ls /var/lib/dkms/broadcom-sta/
cat /var/lib/dkms/broadcom-sta/*/build/make.log

# 커널 헤더 확인
dpkg -l | grep linux-headers
uname -r

# 수동 드라이버 설치 시도
sudo apt install -y broadcom-sta-dkms
# 실패하면:
sudo apt install -y bcmwl-kernel-source
```
