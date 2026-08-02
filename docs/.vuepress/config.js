import { viteBundler } from '@vuepress/bundler-vite'
import { defaultTheme } from '@vuepress/theme-default'
import { defineUserConfig } from 'vuepress'
import { registerComponentsPlugin } from '@vuepress/plugin-register-components'
import { searchPlugin } from '@vuepress/plugin-search'
import { getDirname, path } from 'vuepress/utils'

const __dirname = getDirname(import.meta.url)

export default defineUserConfig({
  bundler: viteBundler(),
  base: '/scripts-ascend/',
  lang: 'zh-CN',
  title: 'Scripts Ascend Wiki',
  description: '昇腾推理开发脚本与工具集 Wiki',

  head: [
    ['link', { rel: 'icon', href: '/scripts-ascend/assets/favicon.svg' }],
  ],

  theme: defaultTheme({
    logo: '/assets/logo.svg',
    repo: 'https://github.com/iKeybot-code/scripts-ascend',
    editLink: false,
    lastUpdated: false,
    contributors: false,

    navbar: [
      { text: '首页', link: '/' },
      { text: '实践指南', link: '/practice/' },
      { text: '调测经验', link: '/debug/' },
      { text: '设计方案', link: '/design/' },
    ],

    sidebar: {
      '/practice/': ['/practice/'],
      '/debug/': [
        '/debug/',
        {
          text: 'DeepSeek V3.1',
          children: ['/debug/deepseek_v31_2p1d_mrv2_report'],
        },
        {
          text: 'MiniMax M2.7',
          children: [
            '/debug/minimax_m27_full_report',
            '/debug/minimax_m27_mrv2_pd_pool_final',
            '/debug/minimax_m27_mrv2_pd_pool_report',
            '/debug/minimax_m27_pd_pool_report',
            '/debug/task_report_minimax_m27_pd_20260727',
            '/debug/MiniMax-M2.7_PD_MRV2_测评报告',
            '/debug/eval_report_20250729',
            '/debug/report_MiniMax_M2.7_MRV2_PD_AIME2025',
          ],
        },
      ],
      '/design/': ['/design/'],
    },
  }),

  plugins: [
    registerComponentsPlugin({
      componentsDir: path.resolve(__dirname, './components'),
    }),
    searchPlugin(),
  ],
})
