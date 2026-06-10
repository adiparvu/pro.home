export default function Loading() {
  return (
    <div className="flex flex-col items-center gap-4 px-4 py-8 md:px-6 animate-pulse">
      <div className="h-8 w-32 rounded-xl glass-light" />
      <div className="h-64 w-full max-w-sm rounded-2xl glass-light" />
      <div className="h-10 w-40 rounded-xl glass-light" />
    </div>
  )
}
