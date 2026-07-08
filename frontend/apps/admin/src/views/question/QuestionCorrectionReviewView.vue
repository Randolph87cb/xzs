<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>改错审核</h1>
        <p>审核学生提交的错题改错，并直接修订为合格版本。</p>
      </div>
      <div class="admin-page__actions">
        <el-button @click="loadData">查询</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters" :model="query" inline>
      <el-form-item label="状态">
        <el-select v-model="query.reviewStatus" clearable placeholder="全部" style="width: 180px">
          <el-option label="待审核" value="SUBMITTED" />
          <el-option label="已通过" value="APPROVED" />
          <el-option label="未通过" value="REJECTED" />
        </el-select>
      </el-form-item>
    </el-form>

    <el-table :data="records" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column label="学生" width="140">
        <template #default="{ row }">{{ row.real_name || row.user_name }}</template>
      </el-table-column>
      <el-table-column label="题干" min-width="260" show-overflow-tooltip>
        <template #default="{ row }">{{ stripHtml(row.title) }}</template>
      </el-table-column>
      <el-table-column label="状态" width="110">
        <template #default="{ row }">{{ statusText(row.review_status) }}</template>
      </el-table-column>
      <el-table-column prop="submit_time" label="提交时间" width="170" />
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button size="small" type="primary" @click="openReview(row.id)">审核</el-button>
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

    <el-dialog v-model="reviewVisible" title="改错审核" width="860px">
      <div v-if="detail" class="correction-review">
        <section>
          <h3>题干</h3>
          <QuestionMarkdown :content="detail.title || ''" />
          <ol v-if="questionItems.length" class="correction-review__items">
            <li v-for="(item, index) in questionItems" :key="item.itemUuid || item.prefix || index">
              <strong>{{ item.prefix }}.</strong>
              <QuestionMarkdown :content="item.content" inline />
            </li>
          </ol>
          <div class="correction-review__answers">
            <p><strong>学生答案：</strong>{{ formatAnswer(detail.student_answer) }}</p>
            <p><strong>正确答案：</strong>{{ formatAnswer(detail.correct) }}</p>
          </div>
        </section>
        <section class="correction-review__student">
          <h3>学生提交</h3>
          <p><strong>错误原因：</strong>{{ detail.student_wrong_reason }}</p>
          <p><strong>正确思路：</strong>{{ detail.student_correct_thinking }}</p>
        </section>

        <el-form label-width="90px">
          <el-form-item label="审核结果">
            <el-radio-group v-model="reviewForm.reviewResult">
              <el-radio label="APPROVED">通过</el-radio>
              <el-radio label="REJECTED">不通过</el-radio>
            </el-radio-group>
          </el-form-item>
          <el-form-item label="审核意见">
            <el-input v-model="reviewForm.reviewComment" type="textarea" :rows="3" />
          </el-form-item>
          <el-form-item>
            <el-button type="primary" @click="saveReview">保存审核</el-button>
          </el-form-item>
        </el-form>

        <el-table :data="detail.reviewRecords ?? []" border>
          <el-table-column label="审核结果" width="110">
            <template #default="{ row }">{{ statusText(row.review_result) }}</template>
          </el-table-column>
          <el-table-column prop="reviewer_name" label="审核人" width="120" />
          <el-table-column prop="review_comment" label="审核意见" min-width="220" show-overflow-tooltip />
          <el-table-column prop="create_time" label="审核时间" width="170" />
        </el-table>
      </div>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import {
  getAdminQuestionCorrection,
  getAdminQuestionCorrectionPage,
  saveAdminQuestionCorrectionReview,
  type AdminQuestionCorrectionItem,
  type AdminQuestionCorrectionPageRequest,
  type AdminQuestionCorrectionReviewRequest,
  type AdminQuestionEditItem
} from '@xzs/api-client'

const loading = ref(false)
const reviewVisible = ref(false)
const records = ref<AdminQuestionCorrectionItem[]>([])
const detail = ref<AdminQuestionCorrectionItem | null>(null)
const total = ref(0)
const query = reactive<AdminQuestionCorrectionPageRequest>({
  reviewStatus: 'SUBMITTED',
  pageIndex: 1,
  pageSize: 10
})
const reviewForm = reactive<AdminQuestionCorrectionReviewRequest>({
  id: 0,
  reviewResult: 'APPROVED',
  reviewComment: ''
})
const questionItems = computed(() => normalizeQuestionItems(detail.value?.items))

loadData()

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminQuestionCorrectionPage(query)
    records.value = result.response?.list ?? []
    total.value = result.response?.total ?? 0
  } finally {
    loading.value = false
  }
}

async function openReview(id: number) {
  const result = await getAdminQuestionCorrection(id)
  detail.value = result.response ?? null
  if (!detail.value) return
  reviewForm.id = id
  reviewForm.reviewResult = 'APPROVED'
  reviewForm.reviewComment = ''
  reviewVisible.value = true
}

async function saveReview() {
  if (reviewForm.reviewResult === 'REJECTED' && !reviewForm.reviewComment?.trim()) {
    ElMessage.error('不通过时请填写审核意见')
    return
  }
  const result = await saveAdminQuestionCorrectionReview(reviewForm)
  ElMessage.success(result.message || '改错审核已保存')
  await openReview(reviewForm.id)
  await loadData()
}

function statusText(status?: string) {
  const map: Record<string, string> = {
    SUBMITTED: '待审核',
    APPROVED: '已通过',
    REJECTED: '未通过'
  }
  return map[status ?? ''] ?? '未知'
}

function stripHtml(value?: string) {
  return (value ?? '').replace(/<[^>]*>/g, '').slice(0, 120)
}

function normalizeQuestionItems(items: AdminQuestionCorrectionItem['items']): AdminQuestionEditItem[] {
  if (Array.isArray(items)) {
    return items
  }
  if (typeof items !== 'string' || !items.trim()) {
    return []
  }
  try {
    const parsed = JSON.parse(items) as unknown
    return Array.isArray(parsed) ? (parsed as AdminQuestionEditItem[]) : []
  } catch {
    return []
  }
}

function formatAnswer(value?: string | null) {
  if (!value) {
    return '-'
  }
  try {
    const parsed = JSON.parse(value) as unknown
    if (Array.isArray(parsed)) {
      return parsed.join('、') || '-'
    }
  } catch {
    // Plain answer values such as A/B do not need JSON parsing.
  }
  return value
}
</script>

<style scoped>
.correction-review {
  display: grid;
  gap: 14px;
}

.correction-review h3,
.correction-review p {
  margin: 0;
}

.correction-review__student {
  display: grid;
  gap: 8px;
  padding: 12px;
  border: 1px solid #e5e7eb;
  background: #f9fafb;
}

.correction-review__items {
  display: grid;
  gap: 8px;
  margin: 12px 0 0;
  padding-left: 22px;
}

.correction-review__items li {
  padding-left: 4px;
}

.correction-review__answers {
  display: grid;
  gap: 8px;
  margin-top: 12px;
}
</style>
