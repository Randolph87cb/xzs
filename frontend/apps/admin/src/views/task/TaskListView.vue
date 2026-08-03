<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>任务列表</h1>
        <p>管理下发给学生的试卷任务。</p>
      </div>
      <el-button type="primary" @click="router.push('/task/edit')">添加</el-button>
    </header>

    <section class="admin-page__filters">
      <el-select v-model="query.classId" clearable placeholder="班级" @change="search">
        <el-option v-for="item in classOptions" :key="item.id" :label="item.name" :value="item.id" />
      </el-select>
      <el-button type="primary" @click="search">查询</el-button>
    </section>

    <el-table class="desktop-only" :data="tasks" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="title" label="标题" min-width="220" show-overflow-tooltip />
      <el-table-column prop="className" label="班级" min-width="140" />
      <el-table-column prop="createUserName" label="发送人" width="140" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="操作" width="170" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="router.push(`/task/edit?id=${row.id}`)">编辑</el-button>
          <el-button size="small" type="danger" @click="remove(row.id)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <div class="mobile-only">
      <div class="admin-mobile-cards">
        <article v-for="task in tasks" :key="task.id" class="admin-mobile-card">
        <div class="admin-mobile-card__header">
          <strong>{{ task.title || '未命名任务' }}</strong>
          <el-tag size="small" type="info">{{ task.className || '全部班级' }}</el-tag>
        </div>
        <div class="admin-mobile-card__fields">
          <div class="admin-mobile-field">
            <span class="admin-mobile-field__label">发送人</span>
            <span class="admin-mobile-field__value">{{ task.createUserName || '—' }}</span>
          </div>
          <div class="admin-mobile-field">
            <span class="admin-mobile-field__label">创建时间</span>
            <span class="admin-mobile-field__value">{{ task.createTime || '—' }}</span>
          </div>
        </div>
        <div class="admin-mobile-card__actions">
          <el-button type="primary" plain @click="router.push(`/task/edit?id=${task.id}`)">编辑</el-button>
          <el-button type="danger" plain @click="remove(task.id)">删除</el-button>
        </div>
        </article>
        <el-empty v-if="tasks.length === 0" description="暂无任务" />
      </div>
    </div>

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
import { ElMessage, ElMessageBox } from 'element-plus'
import { useRouter } from 'vue-router'
import { deleteAdminTask, getAdminClassOptions, getAdminTaskPage, type AdminClassListItem, type AdminTaskListItem } from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const tasks = ref<AdminTaskListItem[]>([])
const classOptions = ref<AdminClassListItem[]>([])
const total = ref(0)
const query = reactive({ classId: null as number | null, pageIndex: 1, pageSize: 10 })

onMounted(async () => {
  const classResult = await getAdminClassOptions()
  classOptions.value = classResult.response ?? []
  await loadData()
})

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminTaskPage(query)
    const page = result.response
    tasks.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function remove(id: number) {
  await ElMessageBox.confirm('确认删除该任务？', '删除任务', { type: 'warning' })
  const result = await deleteAdminTask(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}
</script>
