import os
from slack_release import post, plain, app_actions, REPO

sha=os.environ['GITHUB_SHA']
os.environ['MAC_TESTER_URL']=f'https://github.com/{REPO}/releases/download/mac-{sha}/KanpekiMac.dmg'
p={'channel':os.environ['SLACK_CHANNEL_ID'],'text':'カンペき Mac版を確認できます',
   'unfurl_links':False,'unfurl_media':False,
   'blocks':[{'type':'header','text':plain('カンペき Mac版を確認できます',150)},
             {'type':'section','text':plain(f'Macビルド {os.environ["GITHUB_RUN_NUMBER"]} / commit {sha[:7]}\n署名・公証済み。ダウンロードして動作をご確認ください。')},
             {'type':'actions','elements':app_actions()+[{'type':'button','text':plain('初回設定',70),'url':f'https://github.com/{REPO}/blob/main/docs/MAC_INSTALL.md'}]}]}
result=post(p)
print('Mac download notification posted; ts='+result['ts'])
