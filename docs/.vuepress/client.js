import { defineClientConfig } from 'vuepress/client'
import { onMounted, watch, nextTick } from 'vue'
import { useRoute, usePageFrontmatter } from '@vuepress/client'
import './styles/index.scss'
import '../stylesheets/extra.css'

export default defineClientConfig({
  setup() {
    const route = useRoute()
    const frontmatter = usePageFrontmatter()

    function loadGiscus() {
      // 跳过禁用了评论的页面
      if (frontmatter.value?.comments === false) return

      // 清理旧的 Giscus 元素
      const oldContainer = document.getElementById('giscus-container')
      if (oldContainer) oldContainer.remove()
      const oldScript = document.querySelector('script[src*="giscus"]')
      if (oldScript) oldScript.remove()

      const content = document.querySelector('.theme-default-content')
      if (!content) return

      const container = document.createElement('div')
      container.id = 'giscus-container'
      container.style.marginTop = '2.5rem'
      container.style.paddingTop = '1.5rem'
      container.style.borderTop = '1px solid var(--c-border)'
      content.appendChild(container)

      const script = document.createElement('script')
      script.src = 'https://giscus.app/client.js'
      script.setAttribute('data-repo', 'iKeybot-code/scripts-ascend')
      script.setAttribute('data-category', 'Announcements')
      script.setAttribute('data-mapping', 'pathname')
      script.setAttribute('data-strict', '1')
      script.setAttribute('data-reactions-enabled', '1')
      script.setAttribute('data-emit-metadata', '0')
      script.setAttribute('data-input-position', 'top')
      script.setAttribute('data-theme', 'https://cdn.jsdelivr.net/gh/iKeybot-code/scripts-ascend@main/docs/giscus-theme-light.css')
      script.setAttribute('data-lang', 'zh-CN')
      script.crossOrigin = 'anonymous'
      script.async = true
      container.appendChild(script)
    }

    onMounted(() => {
      loadGiscus()
    })

    watch(() => route.path, () => {
      nextTick(() => {
        setTimeout(loadGiscus, 150)
      })
    })
  },
})
