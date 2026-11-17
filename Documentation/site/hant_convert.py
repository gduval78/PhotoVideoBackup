#!/usr/bin/env python3
"""zh-Hans -> zh-Hant (Taiwan) converter used to derive the Traditional Chinese texts from the Simplified ones.

  1. a vocabulary pass (PHRASES, longest first) that rewrites mainland terms to the Taiwan ones directly in Traditional
     characters and fixes the words ICU converts wrongly (重复, 回复, 账号…);
  2. quotation marks “” ‘’ -> 「」 『』;
  3. character conversion with ICU (hans2hant.swift, compiled on the fly with swiftc, macOS only).

The result is a machine translation: have it proof-read by a Traditional-Chinese (Taiwan) speaker before relying on it.
Usage as a module: convert(list_of_str) -> list_of_str.
"""
import json, re, subprocess, tempfile
from pathlib import Path

PHRASES = {
    # fixes for ICU's character mapping
    "应用 LUT": "套用 LUT", "应用LUT": "套用 LUT",
    "目标位置": "目的地", "目标": "目的地", "文件名": "檔名",
    "通过": "透過", "运行": "執行", "获取": "取得", "接口": "連接埠", "U 盘": "USB 隨身碟", "U盘": "USB 隨身碟",
    "缩略图": "縮圖", "共享文件夹": "共用資料夾", "文件共享": "檔案共用", "共享名": "共用名稱", "共享": "共用",
    "文本": "文字", "实时": "即時", "全屏": "全螢幕",
    "卡里": "卡裡",
    "重复": "重複", "回复": "回覆", "账号": "帳號", "账户": "帳戶", "发送": "傳送", "并发": "並行",
    # Taiwan vocabulary
    "文件夹": "資料夾", "文件": "檔案", "视频": "影片", "软件": "軟體", "内存": "記憶體", "存储卡": "記憶卡",
    "存储空间": "儲存空間", "存储": "儲存", "保存": "儲存", "设置": "設定", "默认": "預設", "服务器": "伺服器",
    "用户": "使用者", "移动数据": "行動數據", "数据": "資料", "支持": "支援", "连接": "連線", "下载": "下載",
    "硬盘": "硬碟", "磁盘": "磁碟", "屏幕": "螢幕", "打开": "開啟", "导入": "匯入", "导出": "匯出", "日志": "記錄",
    "相册": "相簿", "设备": "裝置", "菜单": "選單", "按钮": "按鈕", "点按": "點一下", "点击": "點選",
    "界面": "介面", "创建": "建立", "重命名": "重新命名", "刷新": "重新整理", "字节": "位元組", "隐私政策": "隱私權政策",
    "占用": "佔用", "跳过": "略過", "缓存": "快取", "登录": "登入", "质量": "品質", "激活": "啟用", "后台": "背景",
    "前台": "前景", "程序": "程式", "分辨率": "解析度", "帧率": "影格率", "笔记本": "筆記型電腦", "链接": "連結",
    "搜索": "搜尋", "兼容": "相容", "优化": "最佳化", "访问": "存取", "内置": "內建", "读卡器": "讀卡機",
    "局域网": "區域網路", "网络": "網路", "信息、电子邮件": "訊息、電子郵件", "信息": "資訊", "配置": "設定",
    "校验": "驗證", "应用程序": "App", "应用": "App", "移动硬盘": "外接硬碟", "固态硬盘": "固態硬碟",
}
QUOTES = {"“": "「", "”": "」", "‘": "『", "’": "』"}
_KEYS = sorted(PHRASES, key=len, reverse=True)
_RE = re.compile("|".join(map(re.escape, _KEYS)))
HERE = Path(__file__).resolve().parent


_CJK = "\u4e00-\u9fff"
_STRAIGHT = re.compile(r'"([^"\\]*[' + _CJK + r'][^"\\]*)"')            # "调色" -> 「調色」
_ESCAPED = re.compile(r'\\"([^"\\]*[' + _CJK + r'][^"\\]*)\\"')       # \"调色\" inside a Python string literal


def _pre(s: str, python_source: bool = False) -> str:
    s = _RE.sub(lambda m: PHRASES[m.group(0)], s)
    s = _ESCAPED.sub(lambda m: "「" + m.group(1) + "」", s)
    if not python_source:  # in Python source a plain "…" is the string delimiter, never a quotation
        s = _STRAIGHT.sub(lambda m: "「" + m.group(1) + "」", s)
    return "".join(QUOTES.get(c, c) for c in s)


def convert(texts, python_source: bool = False):
    texts = [_pre(t, python_source) for t in texts]
    with tempfile.TemporaryDirectory() as d:
        exe, i, o = Path(d) / "h2t", Path(d) / "in.json", Path(d) / "out.json"
        subprocess.run(["swiftc", "-O", str(HERE / "hans2hant.swift"), "-o", str(exe)], check=True, capture_output=True)
        i.write_text(json.dumps(texts, ensure_ascii=False))
        subprocess.run([str(exe), str(i), str(o)], check=True)
        return json.loads(o.read_text())


if __name__ == "__main__":
    import sys
    print("\n".join(convert(sys.stdin.read().splitlines())))
