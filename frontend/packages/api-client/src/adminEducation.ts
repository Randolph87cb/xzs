import { post, type ApiResponse } from './request'
import type { AdminPageResponse } from './adminUser'

export interface AdminSubjectPageRequest {
  pageIndex: number
  pageSize: number
  id?: number
  level?: number
}

export interface AdminSubjectListItem {
  id: number
  name: string
  level?: number
  levelName?: string
}

export function getAdminSubjectPage(
  request: AdminSubjectPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminSubjectListItem>>> {
  return post<AdminPageResponse<AdminSubjectListItem>>('/api/admin/education/subject/page', request)
}
