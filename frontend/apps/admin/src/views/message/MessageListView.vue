<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>消息列表</h1>
        <p>查看系统已发送的站内消息。</p>
      </div>
      <el-button type="primary" @click="search">查询</el-button>
    </header>

    <section class="admin-page__filters">
      <el-input v-model="query.sendUserName" clearable placeholder="发送者用户名" @keyup.enter="search" />
    </section>

    <el-table :data="messages" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="title" label="标题" min-width="180" show-overflow-tooltip />
      <el-table-column prop="content" label="内容" min-width="240" show-overflow-tooltip />
      <el-table-column prop="sendUserName" label="发送人" width="120" />
      <el-table-column prop="receives" label="接收人" min-width="180" show-overflow-tooltip />
      <el-table-column prop="readCount" label="已读数" width="90" />
      <el-table-column prop="receiveUserCount" label="接收人数" width="100" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
    </el-table>

    <footer class="admin-page__pagination">
      <el-pagination
        v-model:current-page="query.pageIndex"
        v-model:page-size="query.pageSize"
        background
        layout="total, sizes, prev, pager, next"
        :page-sizes="[10, 20, 50]"
        :total="total"
        @size-change="loadData"
        @current-change="loadData"
      />
    </footer>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { getAdminMessagePage, type AdminMessageListItem } from '@xzs/api-client'

const loading = ref(false)
const messages = ref<AdminMessageListItem[]>([])
const total = ref(0)
const query = reactive({
  sendUserName: '',
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadData)

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminMessagePage(query)
    const page = result.response
    messages.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}
</script>
