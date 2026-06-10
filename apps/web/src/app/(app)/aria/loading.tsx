export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-20 rounded-xl glass-light" />
      <div className="h-32 rounded-2xl glass-light" />
      <div className="flex flex-col gap-3 mt-4">
        <div className="h-16 w-3/4 rounded-2xl glass-light self-end" />
        <div className="h-20 rounded-2xl glass-light" />
        <div className="h-12 w-2/3 rounded-2xl glass-light self-end" />
        <div className="h-28 rounded-2xl glass-light" />
      </div>
    </div>
  )
}
