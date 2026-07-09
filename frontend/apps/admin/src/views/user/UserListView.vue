<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>{{ roleTitle }}列表</h1>
        <p>管理{{ roleTitle }}账号、状态和基础资料。</p>
      </div>
      <el-button type="primary" @click="router.push(editPath)">添加</el-button>
    </header>

    <section class="admin-page__filters">
      <el-input v-model="query.userName" clearable placeholder="用户名" @keyup.enter="search" />
      <el-button type="primary" @click="search">查询</el-button>
    </section>

    <el-table :data="users" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="userName" label="用户名" min-width="150" />
      <el-table-column prop="realName" label="真实姓名" min-width="150" />
      <el-table-column label="性别" width="80">
        <template #default="{ row }">{{ formatSex(row.sex) }}</template>
      </el-table-column>
      <el-table-column prop="phone" label="手机号" min-width="140" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '启用' : '禁用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="280" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="toggleStatus(row as AdminUserListItem)">
            {{ row.status === 1 ? '禁用' : '启用' }}
          </el-button>
          <el-button size="small" @click="router.push(`${editPath}?id=${row.id}`)">编辑</el-button>
          <el-button size="small" @click="router.push(`/log/user/list?userId=${row.id}`)">日志</el-button>
          <el-button size="small" type="danger" @click="remove(row.id)">删除</el-button>
        </template>
      </el-table-column>
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
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  changeAdminUserStatus,
  deleteAdminUser,
  getAdminUserPage,
  type AdminUserListItem
} from '@xzs/api-client'

const props = defineProps<{
  role: 1 | 2 | 3
}>()

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const users = ref<AdminUserListItem[]>([])
const total = ref(0)
const query = reactive({
  userName: '',
  role: props.role,
  pageIndex: 1,
  pageSize: 10
})
const roleTitle = computed(() => {
  if (props.role === 1) return '学生'
  if (props.role === 2) return '老师'
  return '管理员'
})
const editPath = computed(() => {
  if (props.role === 1) return '/user/student/edit'
  if (props.role === 2) return '/user/teacher/edit'
  return '/user/admin/edit'
})

onMounted(loadData)
watch(
  () => route.path,
  () => {
    query.role = props.role
    search()
  }
)

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    query.role = props.role
    const result = await getAdminUserPage(query)
    const page = result.response
    users.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function toggleStatus(row: AdminUserListItem) {
  const result = await changeAdminUserStatus(row.id)
  row.status = result.response ?? row.status
  ElMessage.success(result.message || '状态已更新')
}

async function remove(id: number) {
  await ElMessageBox.confirm('确认删除该用户？', '删除用户', { type: 'warning' })
  const result = await deleteAdminUser(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}

function formatSex(value?: number) {
  if (value === 1) return '男'
  if (value === 2) return '女'
  return ''
}
</script>
