<script setup lang="ts">
import { computed } from 'vue'
import { usePageData } from 'vuepress/client'

const page = usePageData()

const headers = computed(() => {
  if (!page.value?.headers) return []
  return page.value.headers.filter(h => h.level === 2 || h.level === 3)
})
</script>

<template>
  <nav v-if="headers.length > 0" class="toc-sidebar">
    <h3 class="toc-title">目录</h3>
    <ul class="toc-list">
      <li
        v-for="header in headers"
        :key="header.slug"
        :class="['toc-item', `toc-level-${header.level}`]"
      >
        <a :href="`#${header.slug}`" class="toc-link">{{ header.title }}</a>
      </li>
    </ul>
  </nav>
</template>

<style lang="scss">
.toc-sidebar {
  position: sticky;
  top: calc(var(--navbar-height) + 2rem);
  width: 220px;
  max-height: calc(100vh - var(--navbar-height) - 4rem);
  overflow-y: auto;
  padding-left: 0;

  @media (max-width: 1280px) {
    display: none;
  }
}

.toc-title {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--c-text);
  margin-bottom: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.toc-list {
  list-style: none;
  padding: 0;
  margin: 0;
  border-left: 1px solid var(--c-border);
}

.toc-item {
  position: relative;
  line-height: 1.45;
}

.toc-level-2 {
  padding: 0.25rem 0 0.25rem 0.75rem;
}

.toc-level-3 {
  padding: 0.15rem 0 0.15rem 1.5rem;
}

.toc-link {
  display: block;
  font-size: 0.82rem;
  color: var(--c-text-light);
  text-decoration: none;
  transition: color 0.2s;
  overflow: hidden;
  text-overflow: ellipsis;

  &:hover {
    color: var(--c-brand);
  }
}
</style>
