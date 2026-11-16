#!/usr/bin/env python3
"""写入验收用的测试数据。"""

import datetime
import json
import os
import sys

LOCAL_TZ = datetime.timezone(datetime.timedelta(hours=8))


def iso(dt):
    return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def item(title, due, all_day=False, notes="", priority=1, done=False, reminder=10, completed_at=None):
    now = datetime.datetime.now(tz=LOCAL_TZ)
    return {
        "id": str(__import__("uuid").uuid4()).upper(),
        "title": title,
        "notes": notes,
        "due": iso(due),
        "isAllDay": all_day,
        "priority": priority,
        "isDone": done,
        "reminderMinutes": reminder,
        "createdAt": iso(now),
        "updatedAt": iso(now),
        "completedAt": iso(completed_at) if completed_at else None,
    }


def day(offset, hour=0, minute=0):
    base = datetime.datetime.now(tz=LOCAL_TZ).replace(hour=0, minute=0, second=0, microsecond=0)
    return base + datetime.timedelta(days=offset, hours=hour, minutes=minute)


def write(path, items):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "schedules.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "items": items}, f, ensure_ascii=False, indent=2)


def main():
    kind = sys.argv[1]
    path = sys.argv[2]
    if kind == "empty":
        os.makedirs(path, exist_ok=True)
        try:
            os.unlink(os.path.join(path, "schedules.json"))
        except FileNotFoundError:
            pass
        return
    if kind == "future":
        write(path, [
            item("交季度总结", day(1, 9, 0), priority=2, notes="先补数据"),
            item("整理书架", day(2, 0, 0), all_day=True, reminder=None),
            item("牙医复诊", day(4, 15, 30), priority=1),
        ])
        return
    if kind == "today":
        write(path, [
            item("整理桌面", day(0, 0, 0), all_day=True, priority=0, reminder=None),
            item("交季度总结", day(1, 9, 0), priority=1),
        ])
        return
    if kind == "demo":
        write(path, [
            item("提交季度报告", day(-1, 18, 0), priority=2, notes="把 Q4 数据补齐后发给张总", reminder=30),
            item("项目周会", day(0, 10, 30), priority=2, notes="会议室 A，准备进度截图"),
            item("整理本周待办", day(0, 14, 0)),
            item("买牛奶和面包", day(0, 0, 0), all_day=True, priority=0, reminder=None),
            item("牙医复诊", day(1, 9, 0), notes="带上病历本", reminder=30),
            item("读书笔记：深度工作", day(2, 0, 0), all_day=True, priority=0, reminder=None),
            item("提交报销单", day(4, 17, 0), reminder=60),
            item("给妈妈打电话", day(-2, 20, 0), done=True, reminder=None,
                 completed_at=datetime.datetime.now(tz=LOCAL_TZ)),
        ])
        return
    raise SystemExit(f"未知数据类型: {kind}")


if __name__ == "__main__":
    main()