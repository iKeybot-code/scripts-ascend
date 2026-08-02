<script setup lang="ts">
import type { Slot } from '@vuepress/helper/client'
import { computed, ref } from 'vue'
import { onContentUpdated } from 'vuepress/client'

import { useData } from '@theme/useData'
import { useScrollPromise } from '@theme/useScrollPromise'
import { useSidebarItems } from '@theme/useSidebarItems'
import VPFadeSlideYTransition from '@theme/VPFadeSlideYTransition.vue'
import VPHome from '@theme/VPHome.vue'
import VPNavbar from '@theme/VPNavbar.vue'
import VPPage from '@theme/VPPage.vue'
import VPSidebar from '@theme/VPSidebar.vue'
import TOC from './TOC.vue'

defineSlots<{
  'navbar'?: Slot
  'navbar-before'?: Slot
  'navbar-after'?: Slot
  'sidebar'?: Slot
  'sidebar-top'?: Slot
  'sidebar-bottom'?: Slot
  'page'?: Slot
  'page-top'?: Slot
  'page-bottom'?: Slot
  'page-content-top'?: Slot
  'page-content-bottom'?: Slot
}>()

const { frontmatter, page, themeLocale } = useData()

// navbar
const shouldShowNavbar = computed(
  () => frontmatter.value.navbar ?? themeLocale.value.navbar ?? true,
)

// sidebar
const sidebarItems = useSidebarItems()
const isSidebarOpen = ref(false)
const toggleSidebar = (to?: boolean): void => {
  isSidebarOpen.value = typeof to === 'boolean' ? to : !isSidebarOpen.value
}
const touchStart = { x: 0, y: 0 }
const onTouchStart = ({ changedTouches }: TouchEvent): void => {
  touchStart.x = changedTouches[0].clientX
  touchStart.y = changedTouches[0].clientY
}
const onTouchEnd = ({ changedTouches }: TouchEvent): void => {
  const dx = changedTouches[0].clientX - touchStart.x
  const dy = changedTouches[0].clientY - touchStart.y
  if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 40) {
    if (dx > 0 && touchStart.x <= 80) toggleSidebar(true)
    else toggleSidebar(false)
  }
}

// external-link-icon
const enableExternalLinkIcon = computed(
  () =>
    frontmatter.value.externalLinkIcon ??
    themeLocale.value.externalLinkIcon ??
    true,
)

// container classes
const containerClass = computed(() => [
  {
    'no-navbar': !shouldShowNavbar.value,
    'no-sidebar': sidebarItems.value.length === 0,
    'sidebar-open': isSidebarOpen.value,
    'external-link-icon': enableExternalLinkIcon.value,
    'has-toc': !frontmatter.value.home && (frontmatter.value.toc !== false),
  },
  frontmatter.value.pageClass,
])

// close sidebar when content changes
onContentUpdated(() => {
  toggleSidebar(false)
})

// handle scrollBehavior with transition
const scrollPromise = useScrollPromise()
const onBeforeEnter = scrollPromise.resolve
const onBeforeLeave = scrollPromise.pending
</script>

<template>
  <div
    class="vp-theme-container"
    :class="containerClass"
    vp-container
    @touchstart="onTouchStart"
    @touchend="onTouchEnd"
  >
    <slot name="navbar">
      <VPNavbar v-if="shouldShowNavbar" @toggle-sidebar="toggleSidebar">
        <template #before>
          <slot name="navbar-before" />
        </template>
        <template #after>
          <slot name="navbar-after" />
        </template>
      </VPNavbar>
    </slot>

    <div class="vp-sidebar-mask" @click="toggleSidebar(false)" />

    <slot name="sidebar">
      <VPSidebar>
        <template #top>
          <slot name="sidebar-top" />
        </template>
        <template #bottom>
          <slot name="sidebar-bottom" />
        </template>
      </VPSidebar>
    </slot>

    <slot name="page">
      <VPFadeSlideYTransition
        @before-enter="onBeforeEnter"
        @before-leave="onBeforeLeave"
      >
        <VPHome v-if="frontmatter.home" />
        <div v-else class="vp-page-with-toc-wrapper">
          <VPPage :key="page.path">
            <template #top>
              <slot name="page-top" />
            </template>
            <template #content-top>
              <slot name="page-content-top" />
            </template>
            <template #content-bottom>
              <slot name="page-content-bottom" />
            </template>
            <template #bottom>
              <slot name="page-bottom" />
            </template>
          </VPPage>
          <TOC />
        </div>
      </VPFadeSlideYTransition>
    </slot>
  </div>
</template>

<style lang="scss">
.vp-sidebar-mask {
  position: fixed;
  top: 0;
  left: 0;
  z-index: 9;

  display: none;

  width: 100vw;
  height: 100vh;
}

.vp-page-with-toc-wrapper {
  display: flex;
  justify-content: center;

  .vp-page {
    flex: 1;
    min-width: 0;
    max-width: var(--content-width);
    margin: 0 auto;

    // remove right padding since TOC takes that space
    padding-inline-end: 0;
  }
}

.vp-theme-container {
  // navbar is disabled
  &.no-navbar {
    .vp-sidebar {
      top: 0;

      @media (max-width: 768px) {
        padding-top: 0;
      }
    }

    .vp-page {
      padding-top: 0;
    }

    [vp-content] {
      h1, h2, h3, h4, h5, h6 {
        margin-top: 1.5rem;
        padding-top: 0;
      }
    }

    .vp-page-with-toc-wrapper .vp-page {
      padding-top: 0;
    }
  }

  &.no-sidebar {
    .vp-sidebar {
      display: none;

      @media (max-width: 768px) {
        display: block;
      }
    }

    .vp-page {
      padding-inline-start: 0;
    }

    .vp-page-with-toc-wrapper .vp-page {
      padding-inline-start: 0;
    }
  }

  &.sidebar-open {
    @media (max-width: 768px) {
      .vp-sidebar {
        transform: translateX(0);
      }

      .vp-sidebar-mask {
        display: block;
      }
    }
  }
}
</style>
