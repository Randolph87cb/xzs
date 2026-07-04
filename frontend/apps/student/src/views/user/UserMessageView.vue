<template>
  <section class="user-message">
    <header class="user-message__header">
      <h1>消息中心</h1>
      <el-button :loading="loading" @click="loadMessages">刷新</el-button>
    </header>

    <el-empty v-if="!loading && messages.length === 0" description="暂无消息" />

    <el-collapse v-else v-loading="loading" accordion @change="handleChange">
      <el-collapse-item v-for="item in messages" :key="item.id" :name="item.id">
        <template #title>
          <span class="user-message__title">{{ item.title }}</span>
          <el-tag :type="item.readed ? 'success' : 'warning'">{{ item.readed ? '已读' : '未读' }}</el-tag>
        </template>
        <dl class="user-message__content">
          <div><dt>发送人</dt><dd>{{ item.sendUserName }}</dd></div>
          <div><dt>发送时间</dt><dd>{{ item.createTime }}</dd></div>
          <div><dt>发送内容</dt><dd>{{ item.content }}</dd></div>
        </dl>
      </el-collapse-item>
    </el-collapse>

    <el-pagination
      v-if="total > 0"
      class="user-message__pagination"
      layout="prev, pager, next, total"
      :total="total"
      :page-size="query.pageSize"
      :current-page="query.pageIndex"
      @current-change="handlePageChange"
    />
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { getStudentMessagePage, markStudentMessageRead, type StudentMessage } from '@xzs/api-client'

const loading = ref(false)
const messages = ref<StudentMessage[]>([])
const total = ref(0)
const query = reactive({
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadMessages)

async function loadMessages() {
  loading.value = true
  try {
    const result = await getStudentMessagePage(query)
    const page = result.response
    messages.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function handleChange(name: string | number) {
  if (!name) {
    return
  }

  const message = messages.value.find((item) => item.id === Number(name))
  if (!message || message.readed) {
    return
  }

  await markStudentMessageRead(message.id)
  message.readed = true
}

function handlePageChange(page: number) {
  query.pageIndex = page
  loadMessages()
}
</script>

<style scoped lang="scss">
.user-message {
  display: grid;
  gap: 18px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.user-message__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.user-message__header h1 {
  margin: 0;
  color: #111827;
  font-size: 22px;
}

.user-message__title {
  flex: 1 1 auto;
}

.user-message__content {
  display: grid;
  gap: 8px;
  margin: 0;
}

.user-message__content div {
  display: grid;
  grid-template-columns: 80px minmax(0, 1fr);
  gap: 10px;
}

.user-message__content dt {
  color: #64748b;
}

.user-message__content dd {
  margin: 0;
  color: #111827;
}

.user-message__pagination {
  justify-content: flex-end;
}
</style>
