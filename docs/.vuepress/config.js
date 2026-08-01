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
      '/practice/': [
        {
          text: '实践指南',
          children: ['/practice/'],
        },
      ],
      '/debug/': [
        {
          text: '调测经验',
          children: ['/debug/'],
        },
      ],
      '/design/': [
        {
          text: '设计方案',
          children: ['/design/'],
        },
      ],
    },
  }),

  plugins: [
    registerComponentsPlugin({
      componentsDir: path.resolve(__dirname, './components'),
    }),
    searchPlugin(),
  ],
})
