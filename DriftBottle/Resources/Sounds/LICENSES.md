# 音效来源与许可

除 `sfx_cork_pop` 外，其余 9 个音效均为本项目**原创程序化合成**（Python numpy/scipy 生成波形 → ffmpeg 响度标准化与编码）。
- 来源：`tools/sfx/gen.py`、`tools/sfx/cork.py`（本仓库），可完全复现
- 许可：随本项目发布；作者放弃权利，按 **CC0 1.0** 提供（https://creativecommons.org/publicdomain/zero/1.0/）
- 无需署名，可商用

| 文件 | 内容 | 来源 | 许可 |
|---|---|---|---|
| sfx_waves_loop.caf | 海浪环境音，30 秒无缝循环（IMA4 22 kHz，约 -20 LUFS） | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_throw_whoosh.m4a | 扔瓶出手的风声 | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_splash.m4a | 瓶子入水 | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_net_dip.m4a | 网兜入水（较轻） | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_pick_up.m4a | 捞起瓶子 + 滴水 | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_cork_pop.m4a | 真实红酒瓶塞拔出录音（饱满的“啵”+ 空气感玻璃余韵，约 1.3 秒） | “Wine Cork” by JimmySolorzano — https://freesound.org/people/JimmySolorzano/sounds/785283/ | CC0 1.0（Freesound） |
| sfx_paper_unfold.m4a | 展开信纸 | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_send.m4a | 发送（上行双音） | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_receive.m4a | 收到（下行木琴音） | tools/sfx/gen.py | CC0 1.0（原创） |
| sfx_lighthouse_chime.m4a | 首次收到真人回信的钟声 | tools/sfx/gen.py | CC0 1.0（原创） |

短音效为 AAC 96 kbps 单声道，约 -16～-18 LUFS，峰值 ≤ -1 dBFS，带短淡入淡出。海浪循环使用 CAF/IMA4（无 AAC 编码器延迟，循环无缝）。


## sfx_cork_pop（第三方 CC0 录音）
- 来源：https://freesound.org/people/JimmySolorzano/sounds/785283/ ，作者 JimmySolorzano，许可 CC0 1.0（公有领域，可商用，无需署名）
- 处理：截取瓶塞弹出段，50 Hz 高通、轻度降噪、去除开头静音，响度标准化至约 -16 LUFS（峰值 ≤ -1 dBFS），0.25 秒淡出，AAC 128 kbps
- 注意：当前文件由 Freesound 的公开 MP3 预览（HQ preview）制作。待有人登录 Freesound 后，应下载原始 WAV 按相同处理重新导出替换。
- `tools/sfx/gen.py` 不会再输出 sfx_cork_pop；`tools/sfx/cork.py` 仅为合成实验，未使用。
