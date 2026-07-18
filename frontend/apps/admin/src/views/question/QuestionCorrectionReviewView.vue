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
      <el-form-item label="班级">
        <el-select v-model="query.classId" clearable placeholder="全部" style="width: 180px">
          <el-option v-for="item in classOptions" :key="item.id" :label="item.name" :value="item.id" />
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
      <el-table-column label="AI 预审" width="130">
        <template #default="{ row }">
          <el-tag size="small" :type="aiStatusTagType(row.ai_review_status, row.ai_review_result)">
            {{ aiStatusText(row.ai_review_status, row.ai_review_result) }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="AI 建议" min-width="220" show-overflow-tooltip>
        <template #default="{ row }">
          {{ row.ai_review_comment || row.ai_review_reason || row.ai_review_error_message || '-' }}
        </template>
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
        <section v-if="reviewQuestion && reviewAnswer">
          <h3>题目上下文</h3>
          <QuestionCorrectionContext :question="reviewQuestion" :answer="reviewAnswer" :show-result="false" />
        </section>

        <section class="correction-review__ai">
          <div class="correction-review__section-header">
            <h3>AI 预审</h3>
            <el-tag size="small" :type="aiStatusTagType(detail.aiReview?.status, detail.aiReview?.reviewResult)">
              {{ aiStatusText(detail.aiReview?.status, detail.aiReview?.reviewResult) }}
            </el-tag>
          </div>
          <template v-if="detail.aiReview">
            <p v-if="detail.aiReview.reviewComment"><strong>建议意见：</strong>{{ detail.aiReview.reviewComment }}</p>
            <p v-if="detail.aiReview.reason"><strong>理由：</strong>{{ detail.aiReview.reason }}</p>
            <p v-if="detail.aiReview.confidence !== undefined && detail.aiReview.confidence !== null">
              <strong>置信度：</strong>{{ detail.aiReview.confidence }}
            </p>
            <p v-if="detail.aiReview.errorMessage"><strong>失败原因：</strong>{{ detail.aiReview.errorMessage }}</p>
          </template>
          <p v-else>暂无 AI 预审记录。</p>
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
import { QuestionCorrectionContext } from '@xzs/question-renderer'
import {
  getAdminClassOptions,
  getAdminQuestionCorrection,
  getAdminQuestionCorrectionPage,
  saveAdminQuestionCorrectionReview,
  type AdminClassListItem,
  type AdminQuestionCorrectionItem,
  type AdminQuestionCorrectionPageRequest,
  type AdminQuestionCorrectionReviewRequest,
  type QuestionCorrectionAiReviewResult,
  type QuestionCorrectionAiReviewStatus
} from '@xzs/api-client'

const loading = ref(false)
const reviewVisible = ref(false)
const records = ref<AdminQuestionCorrectionItem[]>([])
const detail = ref<AdminQuestionCorrectionItem | null>(null)
const classOptions = ref<AdminClassListItem[]>([])
const total = ref(0)
const query = reactive<AdminQuestionCorrectionPageRequest>({
  reviewStatus: 'SUBMITTED',
  classId: null,
  pageIndex: 1,
  pageSize: 10
})
const reviewForm = reactive<AdminQuestionCorrectionReviewRequest>({
  id: 0,
  reviewResult: 'APPROVED',
  reviewComment: ''
})
const reviewQuestion = computed(() => {
  if (!detail.value) return null
  return {
    title: detail.value.title ?? '',
    questionType: Number(detail.value.question_type ?? 0),
    items: detail.value.items ?? [],
    analyze: detail.value.analyze ?? '',
    correct: detail.value.correct ?? '',
    correctArray: parseAnswerArray(detail.value.correct)
  }
})
const reviewAnswer = computed(() => {
  if (!detail.value) return null
  return {
    content: detail.value.student_answer ?? '',
    contentArray: parseAnswerArray(detail.value.student_answer),
    doRight: false
  }
})

init()

async function init() {
  const classResult = await getAdminClassOptions()
  classOptions.value = classResult.response ?? []
  await loadData()
}

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
  const aiReview = detail.value.aiReview
  if (
    aiReview?.status === 'SUCCESS' &&
    (aiReview.reviewResult === 'APPROVED' || aiReview.reviewResult === 'REJECTED')
  ) {
    reviewForm.reviewResult = aiReview.reviewResult
    reviewForm.reviewComment = aiReview.reviewComment ?? ''
  } else {
    reviewForm.reviewResult = 'APPROVED'
    reviewForm.reviewComment = ''
  }
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

function aiStatusText(status?: QuestionCorrectionAiReviewStatus, result?: QuestionCorrectionAiReviewResult) {
  if (status === 'SUCCESS') {
    const resultMap: Record<QuestionCorrectionAiReviewResult, string> = {
      APPROVED: '建议通过',
      REJECTED: '建议驳回',
      UNCERTAIN: '不确定'
    }
    return resultMap[result ?? 'UNCERTAIN']
  }
  const map: Record<QuestionCorrectionAiReviewStatus, string> = {
    PENDING: '预审中',
    RUNNING: '预审中',
    FAILED: '预审失败',
    SKIPPED: '未预审',
    SUCCESS: '已预审'
  }
  return status ? map[status] : '无记录'
}

function aiStatusTagType(
  status?: QuestionCorrectionAiReviewStatus,
  result?: QuestionCorrectionAiReviewResult
): 'success' | 'warning' | 'danger' | 'info' {
  if (status === 'SUCCESS') {
    if (result === 'APPROVED') return 'success'
    if (result === 'REJECTED') return 'danger'
    return 'warning'
  }
  if (status === 'FAILED') return 'danger'
  if (status === 'PENDING' || status === 'RUNNING') return 'warning'
  return 'info'
}

function stripHtml(value?: string) {
  return (value ?? '').replace(/<[^>]*>/g, '').slice(0, 120)
}

function parseAnswerArray(value?: string | null) {
  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (!trimmed) {
      return []
    }
    try {
      const parsed = JSON.parse(trimmed) as unknown
      if (Array.isArray(parsed)) {
        return parsed.map((item) => String(item)).filter(Boolean)
      }
    } catch {
      return [trimmed]
    }
    return [trimmed]
  }
  return []
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

.correction-review__section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.correction-review__student {
  display: grid;
  gap: 8px;
  padding: 12px;
  border: 1px solid var(--xzs-border);
  background: var(--xzs-surface-soft);
}

.correction-review__ai {
  display: grid;
  gap: 8px;
  padding: 12px;
  border: 1px solid var(--xzs-border);
  background: #f8fafc;
}
</style>
