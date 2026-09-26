"""Offline, credential-free TAP1 examples. No real weather or audio playback.

All imagery is original, deterministic 1-bit geometry, not downloaded artwork.
These packages exercise the existing runtime without adding firmware code.
"""
import base64
import math
from pathlib import Path

from .app_package import build_package, validate_app
from .app_wire import encode


def image(kind, size=64):
    pixels = bytearray(size * size // 8)
    for y in range(size):
        for x in range(size):
            u, v = (x + .5) / size, (y + .5) / size
            r = math.hypot(u - .5, v - .5)
            if kind == 'sun':
                angle = math.atan2(v - .5, u - .5)
                lit = .20 < r < .25 or (.32 < r < .44 and abs(math.sin(angle * 4)) < .22)
            elif kind in ('cloud', 'rain'):
                lit = (.20 < u < .83 and .46 < v < .67) or math.hypot(u-.39,v-.46)<.20 or math.hypot(u-.65,v-.49)<.16
                if kind == 'rain':
                    lit |= .73 < v < .90 and any(abs(u + .3*v - a)<.025 for a in (.48,.68,.88))
            elif kind == 'album':
                # Moon, orbit and a stepped horizon: high-contrast native cover.
                lit = .34 < r < .36 or math.hypot(u-.56,v-.36)<.16
                lit |= .64 < v < .85 and abs(v-(.76+.06*math.sin(u*20)))<.016
                lit |= .13 < u < .87 and .91 < v < .93
            elif kind == 'laptop':
                lit = (.13<u<.87 and (.17<v<.21 or .66<v<.70)) or (.17<v<.70 and (.13<u<.17 or .83<u<.87)) or (.06<u<.94 and .77<v<.82)
            else:
                raise ValueError(kind)
            if lit:
                pixels[y*(size//8)+x//8] |= 128 >> (x % 8)
    return dict(format='mono1-msb', width=size, height=size,
                pixels=base64.b64encode(pixels).decode())


def c(id, kind, x, y, w, h, **fields):
    return dict(id=id, kind=kind, x=x, y=y, w=w, h=h, **fields)


def t(id, text, x, y, w, font=18):
    return c(id, 'text', x, y, w, font+6, text=text, font=font)


def button(id, text, x, y, w, target):
    return c(id, 'button', x, y, w, 30, text=text, font=18,
             action=dict(type='exit' if target=='system' else 'page', target=target))


def page(id, *items):
    return dict(id=id, components=list(items))


def document(id, name, pages, assets=None):
    return dict(schema=1, id=id, name=name, version=1, entry=pages[0]['id'],
                permissions=[], assets=assets or {}, pages=pages)


def examples():
    brief = document('daily_brief', '每日简报', [
        page('home', t('title','Turbo IO · 我的第一个应用',20,14,490,24),
             t('label','原生组件 / 有界内存 / 无脚本执行',20,54,490),
             c('progress','progress',20,92,490,8,value=75),
             c('next','button',20,120,235,40,text='打开详情',font=20,action=dict(type='page',target='detail')),
             c('exit','button',275,120,235,40,text='退出应用',font=20,action=dict(type='exit',target='system'))),
        page('detail',t('title','内容由你的后端生成',20,24,490,24),
             c('back','button',20,108,490,44,text='返回首页',font=20,action=dict(type='page',target='home')))])
    weather = document('weather_demo', '天气 · 示例', [
        page('now',t('title','北京 · 晴',18,10,260,24),t('demo','示例 / 非实时',358,14,164,16),
             c('sun','image',24,54,64,64,asset='sun'),t('temp','26°',112,48,110,28),
             t('range','19° — 28°',112,86,150,18),t('feels','体感 27° · 东北风 2 级',284,54,238),
             t('humidity','湿度 42% · 空气优',284,88,238),
             button('forecast','未来三天',18,138,158,'forecast'),button('details','生活指数',190,138,158,'details'),button('exit','退出',362,138,158,'system')),
        page('forecast',t('title','未来三天 · 示例数据',18,8,500,20),
             c('sun','image',38,40,48,48,asset='sun_small'),c('cloud','image',214,40,48,48,asset='cloud'),c('rain','image',390,40,48,48,asset='rain'),
             t('today','今天 晴 19—28°',18,94,168,16),t('tomorrow','明天 多云 18—26°',194,94,172,16),t('third','后天 小雨 17—23°',370,94,168,16),
             button('back','返回天气',18,138,244,'now'),button('exit','退出',278,138,244,'system')),
        page('details',t('title','生活指数 · 示例数据',18,8,500,20),
             t('uv','紫外线 中等',18,44,235),t('sport','户外运动 适宜',286,44,235),
             c('uv_bar','progress',18,76,226,8,value=45),c('sport_bar','progress',286,76,226,8,value=82),
             t('note','演示图标、文本、进度条；不代表真实天气。',18,100,504,16),
             button('back','返回天气',18,138,244,'now'),button('exit','退出',278,138,244,'system'))],
        dict(sun=image('sun'),sun_small=image('sun',48),cloud=image('cloud',48),rain=image('rain',48)))
    def player(id, paused):
        return page(id,c('cover','image',18,14,112,112,asset='cover'),
            t('title','夜航 · 原创演示曲目',150,10,372,20),
            t('state','已暂停 · 界面演示' if paused else '播放态演示 · 无音频',150,40,372,16),
            t('lyric','沿着星光，慢慢向前',150,66,372,24),
            c('progress','progress',150,102,366,6,value=30),t('time','01:24 / 04:36 · 固定示例',150,114,366,14),
            button('toggle','继续演示' if paused else '暂停演示',18,144,156,'playing' if paused else 'paused'),
            button('lyrics','查看歌词',190,144,156,'lyrics'),button('queue','曲目 / 退出',362,144,156,'queue'))
    music = document('music_demo','音乐播放器 · 演示',[
        player('playing',False),player('paused',True),
        page('lyrics',t('title','夜航 · 原创歌词排版演示',18,6,504,18),
             t('prev','城市的灯渐渐远去',44,36,466,16),t('current','沿着星光，慢慢向前',44,60,466,24),
             t('next','让晚风带我到明天',44,94,466,16),t('note','固定歌词；未接入网易云账号或音频。',18,118,504,14),
             button('back','返回播放器',18,146,244,'playing'),button('exit','退出',278,146,244,'system')),
        page('queue',t('title','音乐应用 · 能力预览',18,10,504,20),
             t('track','01  夜航 / Turbo Lab / 原创示例',18,48,504),
             t('info','封面、歌词、进度与页面状态均为本地演示。',18,80,504,16),
             t('future','真实播放需手机服务接收眼镜控制事件。',18,108,504,16),
             button('back','返回播放器',18,144,244,'playing'),button('exit','退出',278,144,244,'system'))],dict(cover=image('album',112)))
    device = document('device_demo','设备状态 · 示例',[
        page('home',c('icon','image',18,14,64,64,asset='laptop'),t('title','MacBook Pro · 示例',104,10,416,20),
             t('ram','RAM 可用 37.5 / 128 GB',104,42,416,18),c('ram_bar','progress',104,72,410,8,value=29),
             t('ssd','SSD 可用 1.4 / 2 TB',104,94,416,18),c('ssd_bar','progress',104,123,410,8,value=70),
             button('quota','模型额度',18,144,244,'quota'),button('exit','退出',278,144,244,'system')),
        page('quota',t('title','模型额度 · 固定示例数据',18,8,504,20),
             t('codex','Codex Pro 20x · Weekly 剩余 99%',18,40,504,18),c('codex_bar','progress',18,70,504,8,value=99),
             t('claude','Claude Max 20x · 5h 90% / Weekly 85%',18,92,504,18),c('claude_bar','progress',18,122,504,8,value=85),
             button('back','返回设备',18,144,244,'home'),button('exit','退出',278,144,244,'system'))],dict(laptop=image('laptop')))
    return {'TurboAppSDKExample':brief,'TurboAppSDKWeather':weather,
            'TurboAppSDKMusic':music,'TurboAppSDKDevice':device}


def export(directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    report={}
    for stem,doc in examples().items():
        package=build_package(doc);wire=encode(doc)
        (directory/(stem+'.zip')).write_bytes(package)
        report[stem]=dict(**validate_app(doc),zipBytes=len(package),wireBytes=len(wire))
    return report


if __name__ == '__main__':
    import argparse
    import json
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(export(args.out),ensure_ascii=False,indent=2))
