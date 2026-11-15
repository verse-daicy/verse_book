# Verse 羁绊书境 v1.0 完整部署包

完整可运行版本（非增量补丁），包含：

| 内容 | 说明 |
|---|---|
| `verse-server/verse-demo-1.0.jar` | Spring Boot fat jar（Java 17），内置最终 seed（25 本官方书：20heroes 10 条 tier 分档 + 3 新书 + 白晏/秋立阳 narration 禁「你」版，台词全部 ≤20 字），数据库连接已内置（`verse_v4` 库，开箱即用） |
| `verse-server/public/` | 完整前端静态资源：`index.html`（引用最终 hash `index-7_GayN3w.js`）+ 12 个最终 hash 文件 + 全部封面（23+3 新）+ 全部情绪图（120+15 新，含 `yumu-crush` 最终版）+ 原有资源 |
| `verse-server/deploy.sh` | 一键部署：备份 → 停旧 → 安装 → systemd 注册 → 重启 → 自检 |
| `verse-server/voices.json` | TTS 音色库（缺失时脚本会告警，念书功能可能异常） |
| `verse-server/.env.example` | 环境变量模板（数据库已内置，无需配置；TTS/ARK key 会从旧 v4.3 沿用） |

> 注意：`verse_v4_full.sql` 仅用于**全新库**初始化；线上库已是最终版 25 本，部署脚本不会动数据库。

## 一键部署

解压后目录名需为 `Verse-demo-v1.0`（与脚本默认路径一致）：

```bash
# 上传 zip 到服务器
scp Verse-demo-v1.0.zip root@120.53.86.129:/root/verse/

# 在服务器上解压并部署（传目录）
ssh root@120.53.86.129
cd /root/verse
unzip -o Verse-demo-v1.0.zip
sudo bash /root/verse/Verse-demo-v1.0/verse-server/deploy.sh /root/verse/Verse-demo-v1.0/verse-server