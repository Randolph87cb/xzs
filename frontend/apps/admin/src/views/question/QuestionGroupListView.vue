<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>题组管理</h1>
        <p>维护程序阅读和程序填空的共享题面与有序子题。</p>
      </div>
      <div class="admin-page__actions">
        <el-button @click="loadData">查询</el-button>
        <el-button type="primary" @click="router.push('/exam/question/group/edit')">添加题组</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters" :model="query" inline>
      <el-form-item label="题组 ID">
        <el-input v-model.number="query.id" clearable />
      </el-form-item>
      <el-form-item label="学科">
        <el-select v-model="query.subjectId" clearable placeholder="全部" style="width: 180px">
          <el-option v-for="subject in subjects" :key="subject.id" :label="subject.name" :value="subject.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="题组类型">
        <el-select v-model="query.groupType" clearable placeholder="全部" style="width: 160px">
          <el-option label="程序阅读" :value="1" />
          <el-option label="程序填空" :value="2" />
        </el-select>
      </el-form-item>
      <el-form-item label="知识点">
        <el-input v-model="query.knowledgePoint" clearable />
      </el-form-item>
    </el-form>

    <el-table :data="rows" border>
      <el-table-column prop="id" label="Id" width="80" />
      <el-table-column prop="groupType" label="类型" width="110">
        <template #default="{ row }">{{ groupTypeText(row.groupType) }}</template>
      </el-table-column>
      <el-table-column prop="groupCode" label="题组编号" width="190" show-overflow-tooltip />
      <el-table-column prop="knowledgePoint" label="知识点" width="150" show-overflow-tooltip />
      <el-table-column prop="title" label="共享题面" min-width="260" show-overflow-tooltip />
      <el-table-column prop="questionCount" label="子题数" width="85" />
      <el-table-column prop="totalScore" label="总分" width="80" />
      <el-table-column prop="importSource" label="来源" width="180" show-overflow-tooltip />
      <el-table-column label="操作" width="210" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="previewGroup(row.id)">预览</el-button>
          <el-button size="small" type="primary" @click="editGroup(row.id)">编辑</el-button>
          <el-button size="small" type="danger" @click="removeGroup(row.id)">删除</el-button>
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

    <el-dialog v-model="previewVisible" title="题组预览" width="820px">
      <div v-if="preview" class="question-group-preview">
        <div class="question-group-preview__meta">
          <el-tag>{{ groupTypeText(preview.groupType) }}</el-tag>
          <span>{{ preview.groupCode || `题组 #${preview.id}` }}</span>
          <span>{{ preview.questionCount }} 个子题 / {{ preview.totalScore }} 分</span>
        </div>
        <section class="question-group-preview__shared">
          <QuestionMarkdown :content="preview.title" />
        </section>
        <section v-for="question in preview.questionItems" :key="question.id || question.groupItemOrder || question.title" class="question-group-preview__child">
          <strong>第 {{ question.groupItemOrder }} 小题</strong>
          <QuestionMarkdown :content="question.title" />
        </section>
      </div>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { useRouter } from 'vue-router'
import {
  deleteAdminQuestionGroup,
  getAdminQuestionGroupPage,
  getAdminSubjectPage,
  type AdminQuestionGroupEditModel,
  type AdminQuestionGroupPageRequest,
  type AdminSubjectListItem
} from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const rows = ref<AdminQuestionGroupEditModel[]>([])
const subjects = ref<AdminSubjectListItem[]>([])
const total = ref(0)
const previewVisible = ref(false)
const preview = ref<AdminQuestionGroupEditModel | null>(null)
const query = reactive<AdminQuestionGroupPageRequest>({
  id: null,
  subjectId: null,
  groupType: null,
  knowledgePoint: null,
  status: null,
  pageIndex: 1,
  pageSize: 10
})

loadSubjects()
loadData()

async function loadSubjects() {
  const result = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = result.response?.list ?? []
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminQuestionGroupPage(query)
    rows.value = result.response?.list ?? []
    total.value = result.response?.total ?? 0
    query.pageIndex = result.response?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

function previewGroup(id?: number | null) {
  preview.value = rows.value.find((row) => row.id === id) ?? null
  previewVisible.value = true
}

function editGroup(id?: number | null) {
  if (id) {
    router.push({ path: '/exam/question/group/edit', query: { id } })
  }
}

async function removeGroup(id?: number | null) {
  if (!id) return
  await ElMessageBox.confirm('确认删除该题组？历史试卷快照不会被拆分。', '删除题组', { type: 'warning' })
  const result = await deleteAdminQuestionGroup(id)
  if (result.code === 1) {
    ElMessage.success(result.message || '删除成功')
    await loadData()
  } else {
    ElMessage.error(result.message)
  }
}

function groupTypeText(type: number) {
  return type === 2 ? '程序填空' : '程序阅读'
}
</script>

<style scoped>
.question-group-preview,
.question-group-preview__shared,
.question-group-preview__child {
  display: grid;
  gap: 12px;
}

.question-group-preview__meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
  color: var(--el-text-color-secondary);
}

.question-group-preview__shared,
.question-group-preview__child {
  padding: 14px;
  border: 1px solid var(--el-border-color-lighter);
  border-radius: 6px;
}

.question-group-preview__shared {
  border-color: var(--el-color-primary-light-7);
  background: var(--el-color-primary-light-9);
}
</style>
